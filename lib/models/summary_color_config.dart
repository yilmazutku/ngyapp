import 'package:flutter/material.dart';

import 'appointment_color_palette.dart';

/// Process-wide registry of the admin-configured "Danışanlar Özet" table
/// colors.
///
/// Today a single value is configurable: the background of the seans cells,
/// i.e. the appointments that already took place. The palette itself is shared
/// with the appointment cards ([AppointmentColorPalette]) so the admin always
/// picks from one curated list, and the value is stored by option id so the
/// palette can be re-shaded later without invalidating saved settings.
class SummaryColorsRegistry {
  /// Palette option used until the admin picks something else ("Pembe").
  static const String defaultCompletedAppointmentOptionId = 'pink_200';

  static String? _completedAppointmentOptionId;

  static AppointmentColorOption get defaultCompletedAppointmentOption =>
      AppointmentColorPalette.findById(defaultCompletedAppointmentOptionId) ??
      AppointmentColorPalette.pink;

  /// Current admin override, or null when the built-in default applies.
  static String? get completedAppointmentOptionId =>
      _completedAppointmentOptionId;

  /// Replaces the admin override. An unknown option id is dropped so a stale
  /// Firestore entry can never produce a missing color at render time.
  static void setCompletedAppointmentOptionId(String? optionId) {
    _completedAppointmentOptionId =
        AppointmentColorPalette.findById(optionId) == null ? null : optionId;
  }

  /// Background color of the cells holding a completed appointment's date.
  static Color get completedAppointmentColor =>
      AppointmentColorPalette.findById(_completedAppointmentOptionId)?.color ??
      defaultCompletedAppointmentOption.color;

  /// Foreground color that stays readable on [background]. The admin can pick
  /// a dark color from the palette, so the date is never left unreadable on
  /// its own background.
  static Color readableTextColor(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
}
