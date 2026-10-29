import 'package:intl/intl.dart';

abstract final class Fmt {
  static final DateFormat _date = DateFormat.yMMMd();
  static final DateFormat _dateTime = DateFormat.yMMMd().add_jm();
  static final DateFormat _time = DateFormat.jm();
  static final DateFormat _weekday = DateFormat('EEE, MMM d');
  static final NumberFormat _compact = NumberFormat.compact();
  static final NumberFormat _thousands = NumberFormat.decimalPattern();

  static const String empty = '\u2014';

  static String date(DateTime? d) =>
      d == null ? empty : _date.format(d.toLocal());
  static String dateTime(DateTime? d) =>
      d == null ? empty : _dateTime.format(d.toLocal());
  static String time(DateTime? d) =>
      d == null ? empty : _time.format(d.toLocal());
  static String weekday(DateTime? d) =>
      d == null ? empty : _weekday.format(d.toLocal());

  /// "just now", "5m ago", "3h ago", "2d ago"; older dates show the calendar date.
  static String relative(DateTime? d) {
    if (d == null) return empty;
    final diff = DateTime.now().difference(d);
    if (diff.isNegative) return dateTime(d);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(d);
  }

  static String number(num? v) => v == null ? empty : _thousands.format(v);
  static String compact(num? v) => v == null ? empty : _compact.format(v);

  /// Cost estimates are tiny, so precision grows as the value shrinks. `null` means "not available".
  static String usd(double? v) {
    if (v == null) return 'n/a';
    final digits = v == 0 ? 2 : (v.abs() < 0.01 ? 6 : (v.abs() < 1 ? 4 : 2));
    return NumberFormat.currency(symbol: r'$', decimalDigits: digits).format(v);
  }

  static String percent(double? v, {int digits = 0}) =>
      v == null ? empty : '${v.toStringAsFixed(digits)}%';

  static String latency(num? ms) {
    if (ms == null) return empty;
    return ms >= 1000
        ? '${(ms / 1000).toStringAsFixed(1)} s'
        : '${ms.round()} ms';
  }

  /// `meeting_booked` becomes `Meeting booked`.
  static String sentence(String? snake) {
    if (snake == null || snake.isEmpty) return empty;
    final words = snake.replaceAll('_', ' ').replaceAll('.', ' \u00B7 ');
    return words[0].toUpperCase() + words.substring(1);
  }

  static String initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
