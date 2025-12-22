import 'package:intl/intl.dart';

/// A utility class to standardize date formatting throughout the app
/// Uses Turkish locale for all date/time formatting
class DateFormatter {
  /// Format: 01.02.2023
  static String formatShortDate(DateTime date) {
    return DateFormat('d MMMM y', 'tr_TR').format(date);
  }

  /// Format: 01/02/2023
  static String formatSlashDate(DateTime date) {
    return DateFormat('dd/MM/yyyy', 'tr_TR').format(date);
  }

  /// Format: 01 Şubat 2023
  static String formatLongDate(DateTime date) {
    return DateFormat('dd MMMM yyyy', 'tr_TR').format(date);
  }

  /// Format: 01 Şubat 2023, 14:30
  static String formatLongDateTime(DateTime date) {
    return DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR').format(date);
  }

  /// Format: 14:30
  static String formatTime(DateTime date) {
    return DateFormat('HH:mm', 'tr_TR').format(date);
  }

  /// Format: Şubat 2023
  static String formatMonthYear(DateTime date) {
    return DateFormat('MMMM yyyy', 'tr_TR').format(date);
  }

  /// Format: 2023-02-01
  static String formatIsoDate(DateTime date) {
    return DateFormat('yyyy-MM-dd', 'tr_TR').format(date);
  }

  /// Parse date from string in format: 01.02.2023
  static DateTime parseShortDate(String dateStr) {
    return DateFormat('dd.MM.yyyy', 'tr_TR').parse(dateStr);
  }

  /// Parse date from string in format: 01/02/2023
  static DateTime parseSlashDate(String dateStr) {
    return DateFormat('dd/MM/yyyy', 'tr_TR').parse(dateStr);
  }

  /// Parse date from string in format: 01 Şubat 2023
  static DateTime parseLongDate(String dateStr) {
    return DateFormat('dd MMMM yyyy', 'tr_TR').parse(dateStr);
  }

  /// Parse date from string in format: 14:30
  static DateTime parseTime(String timeStr) {
    return DateFormat('HH:mm', 'tr_TR').parse(timeStr);
  }

  /// Format a date range as a string: 01.02.2023 - 15.02.2023
  static String formatDateRange(DateTime start, DateTime end) {
    return '${formatShortDate(start)} - ${formatShortDate(end)}';
  }

  /// Format a date range with long dates: 01 Şubat 2023 - 15 Şubat 2023
  static String formatLongDateRange(DateTime start, DateTime end) {
    return '${formatLongDate(start)} - ${formatLongDate(end)}';
  }
}