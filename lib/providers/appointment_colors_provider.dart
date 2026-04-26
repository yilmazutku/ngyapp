import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/appointment_color_palette.dart';
import '../models/logger.dart';

/// Provider responsible for the admin-configured appointment-card background
/// colors stored at `admininput/appointmentColors` in Firestore.
///
/// The document stores a single field, [colorsField], holding a map of
/// `{ <slotStorageKey>: <paletteOptionId> }` entries. When loaded, the entries
/// are pushed into [AppointmentColorsRegistry] so [AppointmentType.getBgColor]
/// can pick them up synchronously.
class AppointmentColorsProvider extends ChangeNotifier {
  static const String _collection = 'admininput';
  static const String _docId = 'appointmentColors';
  static const String colorsField = 'colors';
  static const String updatedAtField = 'updatedAt';

  final Logger logger = Logger.forClass(AppointmentColorsProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(_collection).doc(_docId);

  /// Fetches the admin-configured color overrides and pushes them into
  /// [AppointmentColorsRegistry]. Returns the loaded map (empty when unset).
  ///
  /// When [force] is false and the colors have already been loaded in this
  /// session the cached registry contents are returned without a network call.
  Future<Map<AppointmentColorSlot, String>> fetchColors(
      {bool force = false}) async {
    if (_hasLoaded && !force) {
      return AppointmentColorsRegistry.snapshot();
    }
    try {
      final snapshot = await _docRef.get();
      final data = snapshot.data();
      final Map<AppointmentColorSlot, String> overrides = {};
      if (data != null && data[colorsField] is Map) {
        final raw = Map<String, dynamic>.from(data[colorsField] as Map);
        raw.forEach((key, value) {
          final slot = AppointmentColorSlot.fromStorageKey(key);
          if (slot == null || value is! String) return;
          if (AppointmentColorPalette.findById(value) == null) return;
          overrides[slot] = value;
        });
      }
      AppointmentColorsRegistry.setOverrides(overrides);
      _hasLoaded = true;
      logger.info(
          'Loaded {} admin appointment color overrides', [overrides.length]);
      return AppointmentColorsRegistry.snapshot();
    } catch (e) {
      logger.err('Error fetching admin appointment colors: {}', [e]);
      // Keep whatever was already in the registry; don't mark as loaded so a
      // later screen can retry.
      rethrow;
    }
  }

  /// Persists [overrides] to Firestore (overwriting the previous map) and
  /// refreshes the registry.
  Future<void> saveColors(Map<AppointmentColorSlot, String> overrides) async {
    try {
      final payload = <String, String>{};
      overrides.forEach((slot, optionId) {
        if (AppointmentColorPalette.findById(optionId) != null) {
          payload[slot.storageKey] = optionId;
        }
      });
      await _docRef.set({
        colorsField: payload,
        updatedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      AppointmentColorsRegistry.setOverrides(overrides);
      _hasLoaded = true;
      logger.info(
          'Saved {} admin appointment color overrides', [payload.length]);
      notifyListeners();
    } catch (e) {
      logger.err('Error saving admin appointment colors: {}', [e]);
      rethrow;
    }
  }
}
