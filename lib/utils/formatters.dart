import 'package:intl/intl.dart';

final _dayMonth = DateFormat('d MMM');
final _dayMonthYear = DateFormat('d MMM yyyy');
final _dayMonthTime = DateFormat('d MMM, h:mm a');
final _timeOnly = DateFormat('h:mm a');
final _weekdayLong = DateFormat('EEEE, d MMMM yyyy');
final _iso = DateFormat('yyyy-MM-dd HH:mm');

/// Indian-style money formatting — brokers in the target market talk in
/// lakh and crore, not in millions.
String formatMoney(num value) {
  if (value.abs() >= 10000000) {
    return '₹${_trim(value / 10000000)} Cr';
  }
  if (value.abs() >= 100000) {
    return '₹${_trim(value / 100000)} L';
  }
  if (value.abs() >= 1000) {
    return '₹${NumberFormat('#,##,###').format(value.round())}';
  }
  return '₹${value.round()}';
}

String _trim(num v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

/// "₹45 L – ₹60 L", or a single bound when only one is set.
String formatBudgetRange(num min, num max) {
  if (min <= 0 && max <= 0) return 'Budget not set';
  if (min <= 0) return 'Up to ${formatMoney(max)}';
  if (max <= 0) return '${formatMoney(min)}+';
  return '${formatMoney(min)} – ${formatMoney(max)}';
}

String formatDate(DateTime? d) => d == null ? '—' : _dayMonthYear.format(d);

String formatShortDate(DateTime? d) => d == null ? '—' : _dayMonth.format(d);

String formatDateTime(DateTime? d) => d == null ? '—' : _dayMonthTime.format(d);

String formatTime(DateTime? d) => d == null ? '—' : _timeOnly.format(d);

String formatLongDate(DateTime d) => _weekdayLong.format(d);

String formatIso(DateTime d) => _iso.format(d);

/// "Today", "Tomorrow", "3 days overdue", "in 5 days" — the phrasing a
/// follow-up list needs.
String formatRelativeDay(DateTime? d) {
  if (d == null) return 'No date';
  final today = DateUtilsX.startOfDay(DateTime.now());
  final target = DateUtilsX.startOfDay(d);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff < 0) return '${-diff} days overdue';
  if (diff < 7) return 'In $diff days';
  return _dayMonth.format(d);
}

String formatArea(int sqft) => sqft <= 0 ? '—' : '$sqft sq.ft';

String formatBedrooms(int n) => n <= 0 ? 'Any' : '$n BHK';

String pluralise(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

class DateUtilsX {
  const DateUtilsX._();

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime d) => isSameDay(d, DateTime.now());

  /// Combines a calendar date with a wall-clock time.
  static DateTime combine(DateTime date, int hour, int minute) =>
      DateTime(date.year, date.month, date.day, hour, minute);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
