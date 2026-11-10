import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_load_test_run.dart';
import '../utils/storage_upload.dart';
import 'chat_manager_new.dart';
import 'user_provider.dart';

typedef ChatLoadTestFunctionCall = Future<Object?> Function(
  String name,
  Map<String, dynamic> data,
);

class ChatLoadTestProvider extends ChangeNotifier {
  ChatLoadTestProvider({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    String? Function()? currentUid,
    ChatLoadTestFunctionCall? callFunction,
  })  : _dbOverride = db,
        _storageOverride = storage,
        _currentUidOverride = currentUid,
        _callFunctionOverride = callFunction;

  final FirebaseFirestore? _dbOverride;
  final FirebaseStorage? _storageOverride;
  final String? Function()? _currentUidOverride;
  final ChatLoadTestFunctionCall? _callFunctionOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  static const String runsCollection = 'chatLoadTests';
  static const String ticksCollection = 'ticks';
  static const String controlCollection = 'control';
  static const String stopDoc = 'stop';
  static const String _startFunction = 'startChatLoadTest';
  static const String _cleanupFunction = 'cleanupChatLoadTests';
  static const int _listedRuns = 20;
  static const int _deleteConcurrency = 4;
  static const int maxFileNameLength = 80;
  static const String fallbackFileName = 'foto.jpg';
  static const Duration _createTimeout = Duration(seconds: 20);
  static const Duration _startTimeout = Duration(minutes: 5);
  static const Duration _cleanupTimeout = Duration(minutes: 9);

  static const String _noSessionError =
      'Oturum bulunamadı. Lütfen tekrar giriş yapın.';
  static const String _offlineError =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.';
  static const String _createError =
      'Test kaydı oluşturulamadı. İnternet bağlantınızı kontrol edin.';
  static const String _startError = 'Test başlatılamadı.';
  static const String _startTimeoutError =
      'Sunucu zamanında yanıt vermedi. Test yine de başlamış olabilir; '
      'listeyi kontrol edin.';
  static const String _cleanupError =
      'Test fotoğrafları ve kayıtları silinemedi.';
  static const String _cleanupTimeoutError =
      'Silme zamanında bitmedi; sunucuda sürüyor olabilir. Biraz sonra '
      'yeniden temizleyin (tekrar çalıştırmak güvenlidir).';

  String? get currentUid {
    final String? Function()? override = _currentUidOverride;
    return override != null
        ? override()
        : FirebaseAuth.instance.currentUser?.uid;
  }

  bool get isChatOffice {
    final String? uid = currentUid;
    return uid != null && ChatManager.isChatOfficeUid(uid);
  }

  CollectionReference<Map<String, dynamic>> get _runs =>
      _db.collection(runsCollection);

  Stream<List<ChatLoadTestRun>> runsStream() => _runs
      .orderBy('createdAt', descending: true)
      .limit(_listedRuns)
      .snapshots()
      .map((snapshot) => [
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in snapshot.docs)
              ChatLoadTestRun.fromMap(doc.id, doc.data()),
          ]);

  Future<ChatLoadTestStartResult> startRun({
    required ChatLoadTestConfig config,
    required List<ChatLoadTestPhoto> photos,
    ValueChanged<String>? onProgress,
  }) async {
    final DocumentReference<Map<String, dynamic>> runRef = _runs.doc();
    final String? uid = currentUid;
    try {
      await runRef.set({
        'status': ChatLoadTestStatus.preparing.value,
        'createdAt': Timestamp.now(),
        if (uid != null) 'createdBy': uid,
        'requestedUserCount': config.userCount,
        'photosPerUser': config.photosPerUser,
        'totalSteps': config.totalMessages,
        'gapSeconds': config.gapSeconds,
        'startDelaySeconds': config.startDelaySeconds,
        'order': config.order.value,
      }).timeout(_createTimeout);
    } catch (e) {
      throw Exception(_createError);
    }

    try {
      final List<Map<String, dynamic>> staged = [];
      for (int i = 0; i < photos.length; i++) {
        onProgress
            ?.call('Fotoğraflar yükleniyor (${i + 1}/${photos.length})...');
        staged.add(await _stagePhoto(runRef.id, i, photos[i]));
      }

      onProgress?.call('Test kullanıcıları oluşturuluyor...');
      final Object? result = await _call(
        _startFunction,
        config.toRequest(
          runId: runRef.id,
          photos: staged,
          utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        ),
        fallbackError: _startError,
        timeout: _startTimeout,
        timeoutError: _startTimeoutError,
      );
      return ChatLoadTestStartResult.fromResult(runRef.id, result);
    } catch (e) {
      await _markPreparingFailed(runRef, e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _stagePhoto(
    String runId,
    int index,
    ChatLoadTestPhoto photo,
  ) async {
    String fileName = uploadFileName(photo.name);
    final UploadedImage uploaded = await uploadImageWithThumbnail(
      bytes: photo.bytes,
      fileName: fileName,
      mimeType: photo.mimeType,
      refFor: (String preparedName) {
        fileName = preparedName;
        return _storage.ref('$runsCollection/$runId/p${index}_$preparedName');
      },
    );
    return {
      'path': uploaded.ref.fullPath,
      'fileName': fileName,
      'thumbPath': uploaded.thumbRef?.fullPath,
      'width': uploaded.size?.width,
      'height': uploaded.size?.height,
    };
  }

  static String uploadFileName(String name) {
    final String clean =
        sanitizeStorageFileName(name, fallback: fallbackFileName)
            .replaceFirst(RegExp(r'^\.+'), '')
            .trim();
    if (clean.isEmpty) return fallbackFileName;
    if (clean.length <= maxFileNameLength) return clean;
    final int dot = clean.lastIndexOf('.');
    final String extension =
        dot > 0 && clean.length - dot <= 10 ? clean.substring(dot) : '';
    return '${clean.substring(0, maxFileNameLength - extension.length)}'
        '$extension';
  }

  Future<void> _markPreparingFailed(
    DocumentReference<Map<String, dynamic>> runRef,
    Object error,
  ) async {
    try {
      await _db.runTransaction((transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> snapshot =
            await transaction.get(runRef);
        if (ChatLoadTestStatus.fromValue(snapshot.data()?['status']) !=
            ChatLoadTestStatus.preparing) {
          return;
        }
        transaction.update(runRef, {
          'status': ChatLoadTestStatus.failed.value,
          'lastError': errorMessage(error),
          'finishedAt': Timestamp.now(),
        });
      });
    } catch (e) {
      return;
    }
  }

  Future<bool> stopRun(String runId) {
    final DocumentReference<Map<String, dynamic>> runRef = _runs.doc(runId);
    return _db.runTransaction<bool>((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(runRef);
      final bool active = snapshot.exists &&
          ChatLoadTestStatus.fromValue(snapshot.data()?['status']).isActive;
      if (active) {
        transaction.update(runRef, {
          'status': ChatLoadTestStatus.cancelled.value,
          'finishedAt': Timestamp.now(),
        });
      }
      transaction.set(
        runRef.collection(controlCollection).doc(stopDoc),
        {'createdAt': Timestamp.now()},
      );
      return active;
    });
  }

  Future<void> resumeRun(String runId) {
    final String chain = 'r${DateTime.now().millisecondsSinceEpoch}';
    return _runs
        .doc(runId)
        .collection(ticksCollection)
        .doc('${chain}_00000')
        .set({
      'chain': chain,
      'fromIndex': 0,
      'createdAt': Timestamp.now(),
    });
  }

  Future<ChatLoadTestCleanupResult> cleanup({
    String? runId,
    required Future<void> Function(String userId) deleteUser,
    ValueChanged<String>? onProgress,
  }) async {
    onProgress?.call('Testler durduruluyor...');
    final List<ChatLoadTestRun> runs = await _runsToClean(runId);
    for (final ChatLoadTestRun run in runs) {
      await stopRun(run.id);
    }

    final List<String> userIds = {
      for (final ChatLoadTestRun run in runs) ...run.testUserIds,
      ...await _markedTestUserIds(runId),
    }.toList();

    int deleted = 0;
    int failed = 0;
    int next = 0;
    Future<void> worker() async {
      while (next < userIds.length) {
        final String userId = userIds[next++];
        try {
          await deleteUser(userId);
          deleted++;
        } catch (e) {
          failed++;
        }
        onProgress?.call('Test kullanıcıları siliniyor '
            '(${deleted + failed}/${userIds.length})...');
      }
    }

    if (userIds.isNotEmpty) {
      onProgress?.call('Test kullanıcıları siliniyor (0/${userIds.length})...');
      await Future.wait([
        for (int i = 0; i < math.min(_deleteConcurrency, userIds.length); i++)
          worker(),
      ]);
    }
    if (failed > 0) {
      return ChatLoadTestCleanupResult(
        deletedUsers: deleted,
        failedUsers: failed,
        deletedRuns: 0,
      );
    }

    onProgress?.call('Test fotoğrafları ve kayıtları siliniyor...');
    try {
      final Object? result = await _call(
        _cleanupFunction,
        {if (runId != null) 'runId': runId},
        fallbackError: _cleanupError,
        timeout: _cleanupTimeout,
        timeoutError: _cleanupTimeoutError,
      );
      final Object? runCount = result is Map ? result['runs'] : null;
      return ChatLoadTestCleanupResult(
        deletedUsers: deleted,
        failedUsers: 0,
        deletedRuns: runCount is num ? runCount.toInt() : 0,
      );
    } catch (e) {
      return ChatLoadTestCleanupResult(
        deletedUsers: deleted,
        failedUsers: 0,
        deletedRuns: 0,
        error: errorMessage(e),
      );
    }
  }

  Future<List<ChatLoadTestRun>> _runsToClean(String? runId) async {
    if (runId != null) {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _runs.doc(runId).get();
      final Map<String, dynamic>? data = snapshot.data();
      return data == null ? const [] : [ChatLoadTestRun.fromMap(runId, data)];
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _runs.get();
    return [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        ChatLoadTestRun.fromMap(doc.id, doc.data()),
    ];
  }

  Future<List<String>> _markedTestUserIds(String? runId) async {
    final Query<Map<String, dynamic>> query = runId == null
        ? _db.collection('users').where('isLoadTestUser', isEqualTo: true)
        : _db.collection('users').where('loadTestRunId', isEqualTo: runId);
    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
    return [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (ChatLoadTestUsers.isTestUserUid(doc.id)) doc.id,
    ];
  }

  static String errorMessage(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<Object?> _call(
    String name,
    Map<String, dynamic> data, {
    required String fallbackError,
    required Duration timeout,
    required String timeoutError,
  }) async {
    final ChatLoadTestFunctionCall? override = _callFunctionOverride;
    if (override != null) return override(name, data);

    final String? idToken =
        await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null) throw Exception(_noSessionError);

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${UserProvider.functionsBaseUrl}/$name'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw Exception(timeoutError);
    } catch (e) {
      throw Exception(_offlineError);
    }

    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (e) {
      decoded = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map ? decoded['result'] : null;
    }
    final Object? error = decoded is Map ? decoded['error'] : null;
    final Object? message = error is Map ? error['message'] : null;
    throw Exception(message is String ? message : fallbackError);
  }
}
