import 'package:intl/intl.dart';

/// A utility class to standardize date formatting throughout the app
/// Uses Turkish locale for all date/time formatting
class DateFormatter {
  static const String _yesterdayLabel = 'Dün';
  static const String _todayLabel = 'Bugün';

  /// Son bir haftada gün adı gösterilir; daha eskisinde tarih.
  static const int _weekdayNameMaxDaysAgo = 6;

  // Sohbette her baloncuk ve listede her satır için biçimlendirilir: kalıp
  // bir kez çözülür (ilk kullanımda; tr_TR verisi uygulama açılışında
  // yüklenir).
  static final DateFormat _timeFormat = DateFormat('HH:mm', 'tr_TR');
  static final DateFormat _numericDateFormat =
      DateFormat('dd.MM.yyyy', 'tr_TR');
  static final DateFormat _weekdayFormat = DateFormat('EEEE', 'tr_TR');
  static final DateFormat _dayMonthFormat = DateFormat('d MMMM', 'tr_TR');
  static final DateFormat _dayMonthYearFormat =
      DateFormat('d MMMM y', 'tr_TR');

  /// Sohbet listesindeki son mesaj zamanı (WhatsApp gibi): bugünse "14:05",
  /// dünse "Dün", son bir haftadaysa gün adı ("Salı"), daha eskiyse
  /// "12.09.2026". Takvim günleri karşılaştırılır; cihaz saati geride
  /// kaldığı için "gelecekte" görünen zaman bugün sayılır.
  static String formatChatListTime(DateTime date, {DateTime? now}) {
    final DateTime current = now ?? DateTime.now();
    final int daysAgo = _calendarDaysBetween(date, current);

    if (daysAgo <= 0) return formatTime(date);
    if (daysAgo == 1) return _yesterdayLabel;
    if (daysAgo <= _weekdayNameMaxDaysAgo) {
      return _weekdayFormat.format(date);
    }
    return formatNumericDate(date);
  }

  /// Sohbetteki gün ayırıcısı: "Bugün", "Dün", "12 Eylül"; başka yıldaysa
  /// "12 Eylül 2025".
  static String formatChatDayLabel(DateTime date, {DateTime? now}) {
    final DateTime current = now ?? DateTime.now();
    final int daysAgo = _calendarDaysBetween(date, current);

    if (daysAgo <= 0) return _todayLabel;
    if (daysAgo == 1) return _yesterdayLabel;
    return (date.year == current.year ? _dayMonthFormat : _dayMonthYearFormat)
        .format(date);
  }

  /// İki anın takvim günü farkı ([to] - [from]); saat ve yaz saati farkı
  /// sonucu değiştirmez.
  static int _calendarDaysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  /// İki an aynı takvim gününde mi.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Numeric date shown across the app / dialogs: 01.02.2023 (gg.aa.yyyy)
  static String formatNumericDate(DateTime date) {
    return _numericDateFormat.format(date);
  }

  /// Numeric date with time: 01.02.2023 14:30 (gg.aa.yyyy SS:dd)
  static String formatNumericDateTime(DateTime date) {
    return DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(date);
  }

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
    return _timeFormat.format(date);
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