import 'package:intl/intl.dart';

class DateTimeFormatter {
  const DateTimeFormatter._();

  static String conversationTime(DateTime time) {
    final now = DateTime.now();
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      return DateFormat.Hm().format(time);
    }
    return DateFormat('MM-dd').format(time);
  }

  /// Short request timestamp: time of day for today, date and time otherwise.
  static String requestTime(DateTime time) {
    final now = DateTime.now();
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      return DateFormat.Hm().format(time);
    }
    return DateFormat('MM-dd HH:mm').format(time);
  }
}
