import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../models/special_line_model.dart';

/// Provider responsible for the admin-configured "special lines" list stored at
/// `admininput/speciallines` in Firestore.
///
/// The document stores a single field, [linesField], holding an array of
/// `{ prefix, hasNumber }` maps. When loaded, the entries are pushed into
/// [SpecialLinesRegistry] so the formatter and docx parser can pick them up
/// synchronously.
class SpecialLinesProvider extends ChangeNotifier {
  static const String _collection = 'admininput';
  static const String _docId = 'speciallines';
  static const String linesField = 'lines';
  static const String updatedAtField = 'updatedAt';

  final Logger logger = Logger.forClass(SpecialLinesProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(_collection).doc(_docId);

  /// Fetches the admin-configured special lines and pushes them into
  /// [SpecialLinesRegistry]. Returns the loaded list (empty when unset).
  ///
  /// When [force] is false and the lines have already been loaded in this
  /// session the cached registry contents are returned without a network call.
  Future<List<SpecialLineConfig>> fetchSpecialLines({bool force = false}) async {
    if (_hasLoaded && !force) {
      return SpecialLinesRegistry.custom;
    }
    try {
      final snapshot = await _docRef.get();
      final data = snapshot.data();
      final List<SpecialLineConfig> lines = [];
      if (data != null && data[linesField] is List) {
        for (final raw in (data[linesField] as List)) {
          if (raw is Map) {
            lines.add(SpecialLineConfig.fromMap(
                Map<String, dynamic>.from(raw)));
          }
        }
      }
      SpecialLinesRegistry.setCustomLines(lines);
      _hasLoaded = true;
      logger.info('Loaded {} admin special lines', [lines.length]);
      return SpecialLinesRegistry.custom;
    } catch (e) {
      logger.err('Error fetching admin special lines: {}', [e]);
      // Keep whatever was already in the registry; don't mark as loaded so a
      // later screen can retry.
      rethrow;
    }
  }

  /// Persists [lines] to Firestore (overwriting the previous list) and
  /// refreshes the registry.
  Future<void> saveSpecialLines(List<SpecialLineConfig> lines) async {
    try {
      await _docRef.set({
        linesField: lines.map((c) => c.toMap()).toList(),
        updatedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      SpecialLinesRegistry.setCustomLines(lines);
      _hasLoaded = true;
      logger.info('Saved {} admin special lines', [lines.length]);
      notifyListeners();
    } catch (e) {
      logger.err('Error saving admin special lines: {}', [e]);
      rethrow;
    }
  }
}
