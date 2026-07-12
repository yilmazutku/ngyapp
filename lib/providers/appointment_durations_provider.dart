import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/appointment_duration_config.dart';
import '../models/logger.dart';

/// Provider responsible for the admin-configured default appointment durations
/// stored at `admininput/appointmentDurations` in Firestore.
///
/// The document stores a single field, [durationsField], holding a map of
/// `{ <slotStorageKey>: <minutes> }` entries. When loaded, the entries are
/// pushed into [AppointmentDurationsRegistry] so
/// [AppointmentType.getDurationForMeetingType] can pick them up synchronously
/// when pre-filling the duration for a new appointment.
class AppointmentDurationsProvider extends ChangeNotifier {
  static const String _collection = 'admininput';
  static const String _docId = 'appointmentDurations';
  static const String durationsField = 'durations';
  static const String updatedAtField = 'updatedAt';

  final Logger logger = Logger.forClass(AppointmentDurationsProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(_collection).doc(_docId);

  /// Fetches the admin-configured duration overrides and pushes them into
  /// [AppointmentDurationsRegistry]. Returns the loaded map (empty when unset).
  ///
  /// When [force] is false and the durations have already been loaded in this
  /// session the cached registry contents are returned without a network call.
  Future<Map<AppointmentDurationSlot, int>> fetchDurations(
      {bool force = false}) async {
    if (_hasLoaded && !force) {
      return AppointmentDurationsRegistry.snapshot();
    }
    try {
      final snapshot = await _docRef.get();
      final data = snapshot.data();
      final Map<AppointmentDurationSlot, int> overrides = {};
      if (data != null && data[durationsField] is Map) {
        final raw = Map<String, dynamic>.from(data[durationsField] as Map);
        raw.forEach((key, value) {
          final slot = AppointmentDurationSlot.fromStorageKey(key);
          final minutes = _asInt(value);
          if (slot == null || minutes == null) return;
          if (!AppointmentDurationsRegistry.isValidMinutes(minutes)) return;
          overrides[slot] = minutes;
        });
      }
      AppointmentDurationsRegistry.setOverrides(overrides);
      _hasLoaded = true;
      logger.info(
          'Loaded {} admin appointment duration overrides', [overrides.length]);
      return AppointmentDurationsRegistry.snapshot();
    } catch (e) {
      logger.err('Error fetching admin appointment durations: {}', [e]);
      // Keep whatever was already in the registry; don't mark as loaded so a
      // later screen can retry.
      rethrow;
    }
  }

  /// Persists [overrides] to Firestore (overwriting the previous map) and
  /// refreshes the registry. Out-of-range values are dropped.
  Future<void> saveDurations(Map<AppointmentDurationSlot, int> overrides) async {
    try {
      final payload = <String, int>{};
      overrides.forEach((slot, minutes) {
        if (AppointmentDurationsRegistry.isValidMinutes(minutes)) {
          payload[slot.storageKey] = minutes;
        }
      });
      await _docRef.set({
        durationsField: payload,
        updatedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      AppointmentDurationsRegistry.setOverrides(overrides);
      _hasLoaded = true;
      logger.info(
          'Saved {} admin appointment duration overrides', [payload.length]);
      notifyListeners();
    } catch (e) {
      logger.err('Error saving admin appointment durations: {}', [e]);
      rethrow;
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
