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

/// Input formatter restricting a text field to **whole lira**: digits only, so
/// no separator (and therefore no kuruş) can be typed at all.
///
/// Package fees are always entered as whole lira. A subscription's
/// `totalAmount` / `amountPaid` stay `double` in Firestore for backwards
/// compatibility, but every read, write and display of them goes through the
/// whole-lira helpers here.
final List<TextInputFormatter> wholeLiraInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
];

/// Parses a whole-lira text field into an [int]. Returns null when the text is
/// empty or holds anything other than digits — a decimal part is rejected
/// rather than silently rounded.
int? parseWholeLiraOrNull(String text) {
  final s = text.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^\d+$').hasMatch(s)) return null;
  return int.tryParse(s);
}

/// Renders a stored amount for an *editable* whole-lira field: `7200.0` becomes
/// `"7200"`, never `"7200.0"`. Grouping separators are intentionally left out —
/// the text goes straight back into [parseWholeLiraOrNull] on save.
String formatWholeLira(num amount) => amount.round().toString();
