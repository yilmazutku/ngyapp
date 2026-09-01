import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/appointment_color_palette.dart';
import '../models/logger.dart';
import '../models/summary_color_config.dart';

/// Provider responsible for the admin-configured "Danışanlar Özet" table
/// colors stored at `admininput/summaryColors` in Firestore.
///
/// The document holds a single field, [completedAppointmentField], carrying a
/// palette option id from [AppointmentColorPalette]. When loaded it is pushed
/// into [SummaryColorsRegistry] so the summary table can read the color
/// synchronously while it builds its rows.
class SummaryColorsProvider extends ChangeNotifier {
  static const String _collection = 'admininput';
  static const String _docId = 'summaryColors';
  static const String completedAppointmentField = 'completedAppointmentColor';
  static const String updatedAtField = 'updatedAt';

  final Logger logger = Logger.forClass(SummaryColorsProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(_collection).doc(_docId);

  /// Fetches the configured color and pushes it into [SummaryColorsRegistry].
  /// Returns the stored palette option id, or null when the built-in default
  /// applies.
  ///
  /// When [force] is false and the color has already been loaded in this
  /// session the cached value is returned without a network call.
  Future<String?> fetchColors({bool force = false}) async {
    if (_hasLoaded && !force) {
      return SummaryColorsRegistry.completedAppointmentOptionId;
    }
    try {
      final snapshot = await _docRef.get();
      final raw = snapshot.data()?[completedAppointmentField];
      SummaryColorsRegistry.setCompletedAppointmentOptionId(
          raw is String ? raw : null);
      _hasLoaded = true;
      logger.info('Loaded summary completed-appointment color: {}',
          [SummaryColorsRegistry.completedAppointmentOptionId ?? 'varsayılan']);
      return SummaryColorsRegistry.completedAppointmentOptionId;
    } catch (e) {
      // Keep whatever was already in the registry; don't mark as loaded so a
      // later screen can retry.
      logger.err('Error fetching summary colors: {}', [e]);
      rethrow;
    }
  }

  /// Persists the completed-appointment background color and refreshes the
  /// registry. A null (or unknown) [optionId] clears the override and restores
  /// the built-in default.
  Future<void> saveCompletedAppointmentColor(String? optionId) async {
    try {
      final valid =
          AppointmentColorPalette.findById(optionId) == null ? null : optionId;
      await _docRef.set({
        completedAppointmentField: valid,
        updatedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      SummaryColorsRegistry.setCompletedAppointmentOptionId(valid);
      _hasLoaded = true;
      logger.info(
          'Saved summary completed-appointment color: {}', [valid ?? 'varsayılan']);
      notifyListeners();
    } catch (e) {
      logger.err('Error saving summary colors: {}', [e]);
      rethrow;
    }
  }
}
