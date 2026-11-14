import 'package:intl/intl.dart';

class Dates {
  Dates._();

  static final DateFormat time = DateFormat('h:mm a');
  static final DateFormat dayLabel = DateFormat('EEE, MMM d');
  static final DateFormat fullDate = DateFormat('MMM d, yyyy • h:mm a');
  static final DateFormat dateOnly = DateFormat('MMM d, yyyy');
  static final DateFormat monthLabel = DateFormat('MMMM yyyy');
  static final DateFormat fileStamp = DateFormat('yyyyMMdd_HHmm');
  static final DateFormat isoDay = DateFormat('yyyy-MM-dd');

  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  /// Monday-based week start.
  static DateTime startOfWeek(DateTime value) {
    final day = startOfDay(value);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime endOfWeek(DateTime value) =>
      endOfDay(startOfWeek(value).add(const Duration(days: 6)));

  static DateTime startOfMonth(DateTime value) =>
      DateTime(value.year, value.month);

  static DateTime endOfMonth(DateTime value) =>
      DateTime(value.year, value.month + 1, 0, 23, 59, 59, 999);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String relativeLabel(DateTime value) {
    final now = DateTime.now();
    if (isSameDay(value, now)) return 'Today';
    if (isSameDay(value, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return dayLabel.format(value);
  }
}
