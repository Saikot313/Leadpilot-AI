import 'package:flutter/foundation.dart';

/// Build-time configuration supplied via `--dart-define`. Never put secrets here.
abstract final class AppConfig {
  static const bool demoMode =
      bool.fromEnvironment('DEMO_MODE', defaultValue: true);
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Workspace used by the backend in demo mode.
  static const String demoWorkspaceId = 'demo-workspace';
  static const String demoUserId = 'demo-user';

  static const Duration requestTimeout = Duration(seconds: 30);

  /// LLM calls can retry on the server, so AI requests get a longer client timeout.
  static const Duration aiTimeout = Duration(seconds: 100);

  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) {
      return _apiBaseUrl.endsWith('/')
          ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
          : _apiBaseUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  static String get apiRoot => '$apiBaseUrl/api/v1';
}
