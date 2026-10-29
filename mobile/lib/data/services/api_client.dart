import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

/// Errors that are safe to show to the user as-is.
abstract interface class UserFacingException implements Exception {
  String get message;
}

class ApiException implements UserFacingException {
  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
    this.details,
  });

  @override
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Object? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isNetwork => code == 'network' || code == 'timeout';

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Message for any error, never leaking internals.
String describeError(Object error) {
  if (error is UserFacingException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Drops null values and blank strings so optional fields are omitted from request bodies.
Map<String, dynamic> compactBody(Map<String, Object?> input) => {
      for (final e in input.entries)
        if (e.value != null &&
            !(e.value is String && (e.value as String).trim().isEmpty))
          e.key: e.value,
    };

typedef TokenProvider = Future<String?> Function();

class ApiClient {
  ApiClient(
      {required TokenProvider tokenProvider, http.Client? client, String? root})
      : _token = tokenProvider,
        _http = client ?? http.Client(),
        _root = root ?? AppConfig.apiRoot;

  final TokenProvider _token;
  final http.Client _http;
  final String _root;

  Future<dynamic> get(String path,
          {Map<String, Object?>? query, Duration? timeout}) =>
      _send('GET', path, query: query, timeout: timeout);

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _send('POST', path,
          body: body, query: query, headers: headers, timeout: timeout);

  Future<dynamic> put(String path, {Object? body, Duration? timeout}) =>
      _send('PUT', path, body: body, timeout: timeout);

  Future<dynamic> patch(String path, {Object? body, Duration? timeout}) =>
      _send('PATCH', path, body: body, timeout: timeout);

  Future<dynamic> delete(String path, {Duration? timeout}) =>
      _send('DELETE', path, timeout: timeout);

  void close() => _http.close();

  Uri _uri(String path, Map<String, Object?>? query) {
    final uri = Uri.parse('$_root$path');
    final params = <String, String>{
      for (final e in (query ?? const <String, Object?>{}).entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final limit = timeout ?? AppConfig.requestTimeout;
    String? token;
    try {
      token = await _token();
    } catch (_) {
      throw const ApiException(
        message:
            'Could not read your sign-in credentials. Please sign in again.',
        statusCode: 401,
        code: 'auth',
      );
    }

    final request = http.Request(method, _uri(path, query))
      ..headers['Accept'] = 'application/json'
      ..headers.addAll(headers ?? const {});
    if (token != null && token.isNotEmpty)
      request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request))
          .timeout(limit);
    } on TimeoutException {
      throw ApiException(
        message: 'The server took too long to respond. Please try again.',
        code: 'timeout',
      );
    } on http.ClientException {
      throw ApiException(
        message:
            'Could not reach the LeadPilot server (${AppConfig.apiBaseUrl}). '
            'Check that the backend is running.',
        code: 'network',
      );
    }

    if (response.statusCode >= 400) throw _errorFrom(response);
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(
        message: 'The server returned an unreadable response.',
        statusCode: response.statusCode,
        code: 'bad_response',
      );
    }
  }

  ApiException _errorFrom(http.Response r) {
    Object? data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    final err = data is Map ? data['error'] : null;
    if (err is Map) {
      var message = (err['message'] ?? '').toString();
      final code = err['code']?.toString();
      final details = err['details'];
      if (code == 'validation_error' &&
          details is List &&
          details.isNotEmpty &&
          details.first is Map) {
        final d = details.first as Map;
        final loc = d['loc'] is List
            ? (d['loc'] as List).where((e) => e != 'body').join('.')
            : '';
        if (loc.isNotEmpty) message = '$loc: ${d['msg']}';
      }
      return ApiException(
        message: message.isEmpty ? _fallback(r.statusCode) : message,
        statusCode: r.statusCode,
        code: code,
        requestId: err['requestId']?.toString(),
        details: details,
      );
    }
    return ApiException(
        message: _fallback(r.statusCode), statusCode: r.statusCode);
  }

  static String _fallback(int status) {
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) return 'You do not have permission to do that.';
    if (status == 404) return 'That item could not be found.';
    if (status == 413) return 'The request was too large.';
    if (status == 429) return 'Too many requests. Please wait a moment.';
    if (status >= 500)
      return 'The server had a problem. Please try again shortly.';
    return 'The request could not be completed.';
  }
}
