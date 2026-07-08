// utils/amount_input_utils.dart

import 'package:flutter/services.dart';

/// Parses a user-entered money amount into a non-negative [double].
///
/// Accepts both Turkish (`1.200,50` / `1200,50`) and dotted (`1200.50`) input
/// by normalizing the thousands/decimal separators before parsing. Returns
/// null when the text is empty, contains a stray character, or is otherwise not
/// a valid positive number (also rejects NaN/Infinity).
double? parseAmountOrNull(String text) {
  String s = text.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;

  // Normalize separators to a plain `1200.50` form.
  if (s.contains('.') && s.contains(',')) {
    // Both present -> dot is the thousands separator, comma is the decimal.
    s = s.replaceAll('.', '');
    s = s.replaceAll(',', '.');
  } else if (s.contains(',')) {
    s = s.replaceAll(',', '.');
  }

  // Only plain digits with an optional single decimal part are allowed.
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;

  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}

/// Input formatter restricting a text field to characters that can form a valid
/// money amount (digits plus the `.` and `,` separators).
final List<TextInputFormatter> amountInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];
