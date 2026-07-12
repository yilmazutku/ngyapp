import 'appointment_model.dart';

/// Identifies a single configurable default-duration slot for appointments.
///
/// Mirrors [AppointmentColorSlot]: each slot represents the
/// (AppointmentType, MeetingType) combinations that produce a distinct default
/// meeting duration in the original hard-coded
/// [AppointmentType.getDurationForMeetingType] logic. Only the *default*
/// duration (the value pre-filled when creating an appointment) is configured
/// here; the admin can still override the duration per appointment.
enum AppointmentDurationSlot {
  haftalikOnline(
    storageKey: 'haftalik_online',
    label: 'Haftalık (Online)',
    defaultMinutes: 20,
  ),
  haftalikF2f(
    storageKey: 'haftalik_f2f',
    label: 'Haftalık (Yüz yüze)',
    defaultMinutes: 30,
  ),
  pb(
    storageKey: 'pb',
    label: 'Prog. Başlangıcı',
    defaultMinutes: 60,
  ),
  og(
    storageKey: 'og',
    label: 'Ön Görüşme',
    defaultMinutes: 45,
  ),
  kgtakip(
    storageKey: 'kgtakip',
    label: 'Kilo Takip',
    defaultMinutes: 30,
  ),
  diger(
    storageKey: 'diger',
    label: 'Diğer',
    defaultMinutes: 30,
  );

  const AppointmentDurationSlot({
    required this.storageKey,
    required this.label,
    required this.defaultMinutes,
  });

  /// Stable key used to persist this slot in Firestore. Kept independent of the
  /// enum name so the enum can be renamed later without invalidating saved data.
  final String storageKey;

  /// Human-readable label shown in the admin Testing page.
  final String label;

  /// Built-in default duration (minutes) used when the admin has not configured
  /// an override for this slot.
  final int defaultMinutes;

  static AppointmentDurationSlot? fromStorageKey(String key) {
    for (final s in AppointmentDurationSlot.values) {
      if (s.storageKey == key) return s;
    }
    return null;
  }

  /// Resolves the slot for a given (AppointmentType, MeetingType) combination.
  /// Mirrors the original hard-coded `getDurationForMeetingType` switch so the
  /// defaults stay consistent with the legacy behavior.
  static AppointmentDurationSlot forAppointment(
      AppointmentType type, MeetingType meetingType) {
    switch (type) {
      case AppointmentType.haftalik:
        return meetingType == MeetingType.online
            ? AppointmentDurationSlot.haftalikOnline
            : AppointmentDurationSlot.haftalikF2f;
      case AppointmentType.pb:
        return AppointmentDurationSlot.pb;
      case AppointmentType.og:
        return AppointmentDurationSlot.og;
      case AppointmentType.kgtakip:
        return AppointmentDurationSlot.kgtakip;
      case AppointmentType.diger:
        return AppointmentDurationSlot.diger;
    }
  }
}

/// Process-wide registry of admin-configured default appointment durations.
///
/// Built-in defaults cover every slot so the app keeps working before the admin
/// doc has been loaded. The admin-configured map is layered on top via
/// [setOverrides] and is consulted by [AppointmentType.getDurationForMeetingType]
/// when pre-filling the duration for a new appointment.
class AppointmentDurationsRegistry {
  /// Sane bounds so a stale / malformed Firestore value can never produce a
  /// zero, negative, or absurd default duration.
  static const int minMinutes = 1;
  static const int maxMinutes = 600;

  static Map<AppointmentDurationSlot, int> _overrides = const {};

  static bool isValidMinutes(int minutes) =>
      minutes >= minMinutes && minutes <= maxMinutes;

  /// Replaces the admin overrides. Out-of-range values are dropped so a stale
  /// Firestore entry can never produce an invalid default at render time.
  static void setOverrides(Map<AppointmentDurationSlot, int> overrides) {
    final cleaned = <AppointmentDurationSlot, int>{};
    overrides.forEach((slot, minutes) {
      if (isValidMinutes(minutes)) cleaned[slot] = minutes;
    });
    _overrides = Map.unmodifiable(cleaned);
  }

  /// Current admin-configured minutes for [slot], or null when the slot falls
  /// back to its built-in default.
  static int? overrideFor(AppointmentDurationSlot slot) => _overrides[slot];

  /// Resolves the default duration (minutes) to use for [slot] (admin override
  /// when configured, the built-in default otherwise).
  static int minutesFor(AppointmentDurationSlot slot) =>
      _overrides[slot] ?? slot.defaultMinutes;

  /// Returns a copy of the current overrides map. Useful for the admin UI to
  /// render the currently saved selections without mutating the registry.
  static Map<AppointmentDurationSlot, int> snapshot() =>
      Map<AppointmentDurationSlot, int>.from(_overrides);
}
