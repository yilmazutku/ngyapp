import 'package:flutter/material.dart';

import 'appointment_color_palette.dart';

/// "Danışanlar Özet" tablosunda ayrı ayrı renklendirilebilen hücre türleri.
///
/// Değerler Firestore'da `admininput/summaryColors` altında düz alanlar olarak
/// [storageKey] ile saklanır; [completedAppointment] eski tek renkli ayarın
/// alan adını koruduğu için kayıtlı seçim güncellemeden sonra da geçerlidir.
/// Renk, palet sonradan yeniden tonlansa da ayar bozulmasın diye
/// [AppointmentColorPalette] seçenek id'siyle tutulur.
enum SummaryColorSlot {
  completedAppointment(
    storageKey: 'completedAppointmentColor',
    label: 'Yapılmış Randevu (Seans)',
    defaultOptionId: 'pink_200',
  ),
  burnedAppointment(
    storageKey: 'burnedAppointmentColor',
    label: 'Yakılmış Randevu (Seans)',
    defaultOptionId: 'yellow_300',
  );

  const SummaryColorSlot({
    required this.storageKey,
    required this.label,
    required this.defaultOptionId,
  });

  final String storageKey;
  final String label;
  final String defaultOptionId;

  AppointmentColorOption get defaultOption =>
      AppointmentColorPalette.findById(defaultOptionId) ??
      AppointmentColorPalette.white;

  static SummaryColorSlot? fromStorageKey(String key) {
    for (final slot in SummaryColorSlot.values) {
      if (slot.storageKey == key) return slot;
    }
    return null;
  }
}

/// Process-wide registry of the admin-configured "Danışanlar Özet" table
/// colors.
///
/// Built-in defaults cover every slot so the table keeps rendering before the
/// admin doc has been loaded. The admin selections are layered on top via
/// [setOverrides] and read synchronously by the summary table while it builds
/// its rows.
class SummaryColorsRegistry {
  static Map<SummaryColorSlot, String> _overrides = const {};

  /// Replaces the admin overrides. Unknown / invalid option ids are dropped so
  /// a stale Firestore entry can never produce a missing color at render time.
  static void setOverrides(Map<SummaryColorSlot, String> overrides) {
    final cleaned = <SummaryColorSlot, String>{};
    overrides.forEach((slot, optionId) {
      if (AppointmentColorPalette.findById(optionId) != null) {
        cleaned[slot] = optionId;
      }
    });
    _overrides = Map.unmodifiable(cleaned);
  }

  /// Current admin-configured option id for [slot], or null when the slot
  /// falls back to its built-in default.
  static String? overrideFor(SummaryColorSlot slot) => _overrides[slot];

  /// Resolves the background color to use for [slot] (admin override when
  /// configured, the built-in default otherwise).
  static Color colorFor(SummaryColorSlot slot) {
    final overrideOpt = AppointmentColorPalette.findById(_overrides[slot]);
    if (overrideOpt != null) return overrideOpt.color;
    return slot.defaultOption.color;
  }

  /// Returns a copy of the current overrides map, for the admin UI to render
  /// the saved selections without mutating the registry.
  static Map<SummaryColorSlot, String> snapshot() =>
      Map<SummaryColorSlot, String>.from(_overrides);

  /// Foreground color that stays readable on [background]. The admin can pick
  /// a dark color from the palette, so the date is never left unreadable on
  /// its own background.
  static Color readableTextColor(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
}
