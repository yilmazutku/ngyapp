import 'package:flutter/material.dart';

import 'appointment_model.dart';

/// A single color the admin can pick from the dropdown when assigning a
/// background color to an appointment slot. Stored by [id] so the admin can
/// rename / re-shade the palette later without invalidating saved values.
class AppointmentColorOption {
  final String id;
  final String label;
  final Color color;

  const AppointmentColorOption({
    required this.id,
    required this.label,
    required this.color,
  });
}

/// Fixed dropdown palette offered to the admin in the Testing page. We keep it
/// intentionally small + named so the admin sees a curated list rather than a
/// full color picker.
class AppointmentColorPalette {
  static const AppointmentColorOption white =
      AppointmentColorOption(id: 'white', label: 'Beyaz', color: Color(0xFFFFFFFF));
  static const AppointmentColorOption greyLight = AppointmentColorOption(
      id: 'grey_50', label: 'Açık Gri', color: Color(0xFFFAFAFA));
  static const AppointmentColorOption grey = AppointmentColorOption(
      id: 'grey_300', label: 'Gri', color: Color(0xFFE0E0E0));

  static const AppointmentColorOption redLight = AppointmentColorOption(
      id: 'red_100', label: 'Açık Kırmızı', color: Color(0xFFFFCDD2));
  static const AppointmentColorOption red = AppointmentColorOption(
      id: 'red_500', label: 'Kırmızı', color: Color(0xFFF44336));

  static const AppointmentColorOption pinkLight = AppointmentColorOption(
      id: 'pink_50', label: 'Açık Pembe', color: Color(0xFFFCE4EC));
  static const AppointmentColorOption pink = AppointmentColorOption(
      id: 'pink_200', label: 'Pembe', color: Color(0xFFF48FB1));

  static const AppointmentColorOption orangeLight = AppointmentColorOption(
      id: 'orange_100', label: 'Açık Turuncu', color: Color(0xFFFFE0B2));
  static const AppointmentColorOption orange = AppointmentColorOption(
      id: 'orange_300', label: 'Turuncu', color: Color(0xFFFFB74D));

  static const AppointmentColorOption yellowLight = AppointmentColorOption(
      id: 'yellow_100', label: 'Açık Sarı', color: Color(0xFFFFF9C4));
  static const AppointmentColorOption yellow = AppointmentColorOption(
      id: 'yellow_300', label: 'Sarı', color: Color(0xFFFFF176));

  static const AppointmentColorOption greenLight = AppointmentColorOption(
      id: 'green_100', label: 'Açık Yeşil', color: Color(0xFFC8E6C9));
  static const AppointmentColorOption green = AppointmentColorOption(
      id: 'green_400', label: 'Yeşil', color: Color(0xFF66BB6A));

  static const AppointmentColorOption tealAccent = AppointmentColorOption(
      id: 'teal_accent', label: 'Açık Camgöbeği', color: Color(0xFF64FFDA));
  static const AppointmentColorOption teal = AppointmentColorOption(
      id: 'teal_300', label: 'Camgöbeği', color: Color(0xFF4DB6AC));

  static const AppointmentColorOption blueLight = AppointmentColorOption(
      id: 'blue_100', label: 'Açık Mavi', color: Color(0xFFBBDEFB));
  static const AppointmentColorOption blue = AppointmentColorOption(
      id: 'blue_400', label: 'Mavi', color: Color(0xFF42A5F5));

  static const AppointmentColorOption purpleLight = AppointmentColorOption(
      id: 'purple_100', label: 'Açık Mor', color: Color(0xFFE1BEE7));
  static const AppointmentColorOption purple = AppointmentColorOption(
      id: 'purple_300', label: 'Mor', color: Color(0xFFBA68C8));

  static const AppointmentColorOption brown = AppointmentColorOption(
      id: 'brown_300', label: 'Kahverengi', color: Color(0xFFA1887F));

  /// All options exposed to the admin. Order = display order in the dropdown.
  static const List<AppointmentColorOption> options = [
    white,
    greyLight,
    grey,
    redLight,
    red,
    pinkLight,
    pink,
    orangeLight,
    orange,
    yellowLight,
    yellow,
    greenLight,
    green,
    tealAccent,
    teal,
    blueLight,
    blue,
    purpleLight,
    purple,
    brown,
  ];

  static AppointmentColorOption? findById(String? id) {
    if (id == null) return null;
    for (final opt in options) {
      if (opt.id == id) return opt;
    }
    return null;
  }
}

/// Identifies a single configurable background-color slot for the appointment
/// cards. Each slot represents the (AppointmentType, MeetingType) combinations
/// that produce a distinct color in [AppointmentType.getBgColor].
enum AppointmentColorSlot {
  haftalikOnline(
    storageKey: 'haftalik_online',
    label: 'Haftalık (Online)',
    defaultOptionId: 'blue_400',
  ),
  haftalikF2f(
    storageKey: 'haftalik_f2f',
    label: 'Haftalık (Yüz yüze)',
    defaultOptionId: 'pink_200',
  ),
  pb(
    storageKey: 'pb',
    label: 'Prog. Başlangıcı',
    defaultOptionId: 'teal_accent',
  ),
  og(
    storageKey: 'og',
    label: 'Ön Görüşme',
    defaultOptionId: 'teal_accent',
  ),
  kgtakip(
    storageKey: 'kgtakip',
    label: 'Kilo Takip',
    defaultOptionId: 'red_500',
  ),
  diger(
    storageKey: 'diger',
    label: 'Diğer',
    defaultOptionId: 'red_500',
  );

  const AppointmentColorSlot({
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

  static AppointmentColorSlot? fromStorageKey(String key) {
    for (final s in AppointmentColorSlot.values) {
      if (s.storageKey == key) return s;
    }
    return null;
  }

  /// Resolves the slot for a given (AppointmentType, MeetingType) combination.
  /// Mirrors the original `AppointmentType.getBgColor` switch so colors stay
  /// consistent with the legacy hard-coded behavior.
  static AppointmentColorSlot forAppointment(
      AppointmentType type, MeetingType meetingType) {
    switch (type) {
      case AppointmentType.haftalik:
        return meetingType == MeetingType.online
            ? AppointmentColorSlot.haftalikOnline
            : AppointmentColorSlot.haftalikF2f;
      case AppointmentType.pb:
        return AppointmentColorSlot.pb;
      case AppointmentType.og:
        return AppointmentColorSlot.og;
      case AppointmentType.kgtakip:
        return AppointmentColorSlot.kgtakip;
      case AppointmentType.diger:
        return AppointmentColorSlot.diger;
    }
  }
}

/// Process-wide registry of admin-configured appointment background colors.
///
/// Built-in defaults cover every slot so the app keeps working before the
/// admin doc has been loaded. The admin-configured map is layered on top via
/// [setOverrides] and is consulted by [AppointmentType.getBgColor] for the
/// appointment-card background color.
class AppointmentColorsRegistry {
  static Map<AppointmentColorSlot, String> _overrides = const {};

  /// Replaces the admin overrides. Unknown / invalid option ids are dropped so
  /// a stale Firestore entry can never produce a missing color at render time.
  static void setOverrides(Map<AppointmentColorSlot, String> overrides) {
    final cleaned = <AppointmentColorSlot, String>{};
    overrides.forEach((slot, optionId) {
      if (AppointmentColorPalette.findById(optionId) != null) {
        cleaned[slot] = optionId;
      }
    });
    _overrides = Map.unmodifiable(cleaned);
  }

  /// Current admin-configured option id for [slot], or null when the slot
  /// falls back to its built-in default.
  static String? overrideFor(AppointmentColorSlot slot) => _overrides[slot];

  /// Resolves the background color to use for [slot] (admin override when
  /// configured, the built-in default otherwise).
  static Color colorFor(AppointmentColorSlot slot) {
    final overrideId = _overrides[slot];
    final overrideOpt = AppointmentColorPalette.findById(overrideId);
    if (overrideOpt != null) return overrideOpt.color;
    return slot.defaultOption.color;
  }

  /// Returns a copy of the current overrides map. Useful for the admin UI
  /// to render the currently saved selections without mutating the registry.
  static Map<AppointmentColorSlot, String> snapshot() =>
      Map<AppointmentColorSlot, String>.from(_overrides);
}
