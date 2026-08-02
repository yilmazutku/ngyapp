import 'package:flutter/material.dart';

/// Shared time picker helper for the whole app.
///
/// Opens the Material time picker directly in text-input mode with no
/// circular dial (TimePickerEntryMode.inputOnly) and forces the 24-hour
/// format, so time selection behaves the same everywhere.
class TimePickerUtils {
  TimePickerUtils._();

  static Future<TimeOfDay?> pickTime(
    BuildContext context, {
    required TimeOfDay initialTime,
  }) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }
}
