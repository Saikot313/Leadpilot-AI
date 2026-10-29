import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Defensive parsing: a missing or malformed field becomes a safe default instead of a crash.
abstract final class Json {
  static Map<String, dynamic> map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static String? str(Object? v) =>
      v == null ? null : (v is String ? v : v.toString());

  static String strOr(Object? v, [String fallback = '']) => str(v) ?? fallback;

  static int? integer(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? number(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool flag(Object? v, [bool fallback = false]) =>
      v is bool ? v : fallback;

  static List<String> strings(Object? v) => v is List
      ? v.whereType<Object>().map((e) => e.toString()).toList()
      : <String>[];

  static List<Map<String, dynamic>> maps(Object? v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  /// Accepts ISO-8601 strings (API) and Firestore Timestamps. Always returns local time.
  static DateTime? date(Object? v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
