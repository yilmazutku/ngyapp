import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/storage_upload.dart';

class PhotoUploadSettingsProvider extends ChangeNotifier {
  PhotoUploadSettingsProvider({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'admininput';
  static const String docId = 'photoUpload';
  static const String compactField = 'compact';
  static const bool defaultCompact = true;
  static const Duration loadTimeout = Duration(seconds: 3);

  final FirebaseFirestore _firestore;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  final Completer<void> _loaded = Completer<void>();
  bool _seedsDefault = false;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection(collection).doc(docId);

  void start({required bool seedsDefault}) {
    _seedsDefault = seedsDefault;
    if (_subscription != null) return;
    _subscription = _docRef.snapshots().listen(
      _apply,
      onError: (Object e) {
        _subscription?.cancel();
        _subscription = null;
      },
    );
  }

  Future<void> ensureLoaded() =>
      _loaded.future.timeout(loadTimeout, onTimeout: () {});

  static UploadImageProfile profileOf(Map<String, dynamic>? data) {
    final Object? compact = data?[compactField];
    return (compact is bool ? compact : defaultCompact)
        ? UploadImageProfile.compact
        : UploadImageProfile.standard;
  }

  void _apply(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final Map<String, dynamic>? data = snapshot.data();
    UploadImageProfile.current = profileOf(data);
    if (!_loaded.isCompleted) _loaded.complete();

    final bool confirmedMissing = !snapshot.metadata.isFromCache &&
        !snapshot.metadata.hasPendingWrites &&
        !(data?.containsKey(compactField) ?? false);
    if (_seedsDefault && confirmedMissing) {
      unawaited(
        _docRef
            .set({compactField: defaultCompact}, SetOptions(merge: true))
            .catchError((Object e) {}),
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
