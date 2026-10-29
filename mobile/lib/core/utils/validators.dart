abstract final class Validators {
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  static String? required(String? v, [String field = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  static String? email(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Email is required';
    if (value.length > 254 || !_email.hasMatch(value))
      return 'Enter a valid email address';
    return null;
  }

  static String? optionalEmail(String? v) {
    final value = v?.trim() ?? '';
    return value.isEmpty ? null : email(value);
  }

  static String? password(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? optionalPhone(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.length > 32) return 'Phone number is too long';
    if (!RegExp(r'^[+\d][\d\s\-()]{5,}$').hasMatch(value))
      return 'Enter a valid phone number';
    return null;
  }

  static String? Function(String?) maxLength(int max,
          [String field = 'This field']) =>
      (v) => (v != null && v.trim().length > max)
          ? '$field must be at most $max characters'
          : null;

  /// Runs validators in order and returns the first error.
  static String? Function(String?) all(
          List<String? Function(String?)> validators) =>
      (v) {
        for (final check in validators) {
          final error = check(v);
          if (error != null) return error;
        }
        return null;
      };
}
