// utils/date_input_utils.dart

import 'package:flutter/services.dart';

/// Parses a `dd<sep>mm<sep>yyyy` string (dots or slashes accepted) into a
/// [DateTime]. Returns null when the value is incomplete or is not a real
/// calendar date (e.g. `31.02.2024`).
DateTime? parseDayMonthYear(String text) {
  final parts = text.split(RegExp(r'[./]'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  // Reject overflow dates like 31.02.2024 that DateTime silently rolls over.
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Formats free digit input into `dd<sep>mm<sep>yyyy`, inserting [separator]
/// automatically after the day and month segments as the user types.
class DateInputFormatter extends TextInputFormatter {
  final String separator;

  DateInputFormatter(this.separator);

  /// Exposes the formatting logic for reuse/testing outside of a text field.
  static String format(String input, String separator) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buffer = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      buffer.write(trimmed[i]);
      if ((i == 1 || i == 3) && i != trimmed.length - 1) {
        buffer.write(separator);
      }
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text, separator);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Date formatter that keeps the two `.` separators permanently visible in a
/// fixed `dd.mm.yyyy` mask. Unlike [DateInputFormatter], the dots are present
/// from the start (an empty field shows [emptyMask]); the user only types the
/// digits, which fill the day/month/year slots left-to-right around the dots.
class MaskedDateInputFormatter extends TextInputFormatter {
  /// Value shown before any digit is entered (dots already in place).
  static const String emptyMask = '..';

  static final RegExp _nonDigits = RegExp(r'[^0-9]');
  static final RegExp _digit = RegExp(r'[0-9]');

  /// Builds the `dd.mm.yyyy` mask from a raw [text] (non-digits are ignored,
  /// digits beyond 8 are dropped). The two dots are always included.
  static String mask(String text) {
    final digits = text.replaceAll(_nonDigits, '');
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;
    final day = trimmed.length >= 2 ? trimmed.substring(0, 2) : trimmed;
    final month = trimmed.length >= 4
        ? trimmed.substring(2, 4)
        : (trimmed.length > 2 ? trimmed.substring(2) : '');
    final year = trimmed.length > 4 ? trimmed.substring(4) : '';
    return '$day.$month.$year';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCursor =
        newValue.text.substring(0, end).replaceAll(_nonDigits, '').length;
    final formatted = mask(newValue.text);

    // Position the cursor right after the nth typed digit, skipping the dots.
    int offset = 0;
    int seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (_digit.hasMatch(formatted[offset])) seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
