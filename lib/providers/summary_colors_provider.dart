import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/appointment_color_palette.dart';
import '../models/logger.dart';
import '../models/summary_color_config.dart';

/// Provider responsible for the admin-configured "Danışanlar Özet" table
/// colors stored at `admininput/summaryColors` in Firestore.
///
/// Each [SummaryColorSlot] is kept as a top-level field named after its
/// `storageKey`, carrying a palette option id from [AppointmentColorPalette].
/// When loaded the entries are pushed into [SummaryColorsRegistry] so the
/// summary table can read the colors synchronously while it builds its rows.
class SummaryColorsProvider extends ChangeNotifier {
  static const String _collection = 'admininput';
  static const String _docId = 'summaryColors';
  static const String updatedAtField = 'updatedAt';

  final Logger logger = Logger.forClass(SummaryColorsProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(_collection).doc(_docId);

  /// Fetches the configured colors and pushes them into
  /// [SummaryColorsRegistry]. Returns the loaded overrides (empty when every
  /// slot falls back to its built-in default).
  ///
  /// When [force] is false and the colors have already been loaded in this
  /// session the cached registry contents are returned without a network call.
  Future<Map<SummaryColorSlot, String>> fetchColors({bool force = false}) async {
    if (_hasLoaded && !force) {
      return SummaryColorsRegistry.snapshot();
    }
    try {
      final data = (await _docRef.get()).data();
      final overrides = <SummaryColorSlot, String>{};
      if (data != null) {
        for (final slot in SummaryColorSlot.values) {
          final raw = data[slot.storageKey];
          if (raw is! String) continue;
          if (AppointmentColorPalette.findById(raw) == null) continue;
          overrides[slot] = raw;
        }
      }
      SummaryColorsRegistry.setOverrides(overrides);
      _hasLoaded = true;
      logger.info('Loaded {} summary color overrides', [overrides.length]);
      return SummaryColorsRegistry.snapshot();
    } catch (e) {
      // Keep whatever was already in the registry; don't mark as loaded so a
      // later screen can retry.
      logger.err('Error fetching summary colors: {}', [e]);
      rethrow;
    }
  }

  /// Persists [overrides] (overwriting the previous selections) and refreshes
  /// the registry. A slot missing from the map — or carrying an unknown option
  /// id — is cleared, so it falls back to its built-in default.
  Future<void> saveColors(Map<SummaryColorSlot, String?> overrides) async {
    try {
      final cleaned = <SummaryColorSlot, String>{};
      final payload = <String, String?>{};
      for (final slot in SummaryColorSlot.values) {
        final optionId = overrides[slot];
        final valid =
            AppointmentColorPalette.findById(optionId) == null ? null : optionId;
        if (valid != null) cleaned[slot] = valid;
        payload[slot.storageKey] = valid;
      }
      await _docRef.set({
        ...payload,
        updatedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      SummaryColorsRegistry.setOverrides(cleaned);
      _hasLoaded = true;
      logger.info('Saved {} summary color overrides', [cleaned.length]);
      notifyListeners();
    } catch (e) {
      logger.err('Error saving summary colors: {}', [e]);
      rethrow;
    }
  }
}
