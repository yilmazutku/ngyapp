import 'dart:async';

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
///
/// A live Firestore listener ([startListening]) keeps every device in sync:
/// without it a device that had already loaded the list would keep serving the
/// stale one for the rest of the app session, so an admin editing the markers
/// on one device would not affect any other device (or any client app) until
/// it was restarted.
class SpecialLinesProvider extends ChangeNotifier {
  static const String _collection = 'admininput';
  static const String _docId = 'speciallines';
  static const String linesField = 'lines';
  static const String updatedAtField = 'updatedAt';

  final Logger logger = Logger.forClass(SpecialLinesProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  /// Whether the live listener is currently attached.
  bool get isListening => _subscription != null;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(_collection).doc(_docId);

  /// Subscribes to the special lines document so remote edits reach this
  /// device immediately. Idempotent; safe to call from every entry point.
  ///
  /// Firestore only bills a read when the document is actually delivered (once
  /// on attach, then once per admin edit), so this is cheaper than re-fetching
  /// on every screen and adds no polling.
  void startListening() {
    if (_subscription != null) return;
    _subscription = _docRef.snapshots().listen(
      (snapshot) {
        final before = _registrySignature();
        SpecialLinesRegistry.setCustomLines(_parseLines(snapshot.data()));
        _hasLoaded = true;
        final after = _registrySignature();
        if (before != after) {
          logger.info('Admin special lines updated remotely: {}', [after]);
          notifyListeners();
        }
      },
      onError: (Object e) {
        // A snapshot listener is dead once it errors (e.g. a permission error
        // raised before sign-in). Drop it so the next fetch re-attaches.
        logger.err('Special lines listener failed: {}', [e]);
        _subscription?.cancel();
        _subscription = null;
      },
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }

  String _registrySignature() =>
      SpecialLinesRegistry.custom.map((c) => c.identityKey).join(' | ');

  List<SpecialLineConfig> _parseLines(Map<String, dynamic>? data) {
    final List<SpecialLineConfig> lines = [];
    if (data != null && data[linesField] is List) {
      for (final raw in (data[linesField] as List)) {
        if (raw is Map) {
          lines.add(SpecialLineConfig.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return lines;
  }

  /// Fetches the admin-configured special lines and pushes them into
  /// [SpecialLinesRegistry]. Returns the loaded list (empty when unset).
  ///
  /// When [force] is false and the lines have already been loaded in this
  /// session the cached registry contents are returned without a network call;
  /// the live listener keeps that cache fresh.
  Future<List<SpecialLineConfig>> fetchSpecialLines({bool force = false}) async {
    startListening();
    if (_hasLoaded && !force) {
      return SpecialLinesRegistry.custom;
    }
    try {
      final snapshot = await _docRef.get();
      final lines = _parseLines(snapshot.data());
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
