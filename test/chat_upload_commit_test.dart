import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/pending_upload.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/utils/storage_upload.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Sıra işlerken Firebase'e dokunulmaz; yalnızca kurucu için.
class _FakeFirestore extends Fake implements FirebaseFirestore {}

class _FakeAuth extends Fake implements FirebaseAuth {}

class _FakeStorage extends Fake implements FirebaseStorage {}

class _FakeRef extends Fake implements Reference {}

const MethodChannel _pathProvider =
    MethodChannel('plugins.flutter.io/path_provider');

const String _chatId = 'user-1';

/// Sıranın cihazda saklandığı anahtar (bkz. ChatManager).
const String _persistedUploadsKey = 'chat_pending_meal_uploads_v1';

Future<void> _waitUntil(bool Function() condition) async {
  for (int i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Dosyalar Storage'a yüklendi (bkz. [UploadObserver.onUploaded]).
void _filesUploaded(PendingUpload upload) => upload.onUploaded(UploadedImage(
      ref: _FakeRef(),
      url: 'https://x/a.jpg',
      thumbRef: null,
      thumbUrl: null,
      thumbBytes: null,
      size: null,
    ));

Future<Set<String>> _persistedKeys() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? raw = prefs.getString(_persistedUploadsKey);
  if (raw == null) return const {};
  final Object? decoded = jsonDecode(raw);
  final Iterable<Object?> entries = decoded is Map
      ? decoded.values
      : decoded is List
          ? decoded
          : const [];
  return {
    for (final Object? entry in entries)
      if (entry is Map) entry['key'] as String,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late ChatManager chat;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('chat_upload_commit_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async => temporary.path);
    SharedPreferences.setMockInitialValues({});
    chat = ChatManager(
      db: _FakeFirestore(),
      auth: _FakeAuth(),
      storage: _FakeStorage(),
    );
  });

  tearDown(() {
    chat.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    temporary.deleteSync(recursive: true);
  });

  PendingUpload uploadOf(Future<void> Function(PendingUpload upload) runner) {
    final File file = File(p.join(temporary.path, 'photo.jpg'))
      ..writeAsStringSync('photo');
    return PendingUpload(
      chatId: _chatId,
      image: XFile(file.path),
      meal: Meals.lunch,
      runner: runner,
    );
  }

  test('dosyalar yüklenince iptal edilemez; kayıt bitince baloncuk kalkar',
      () async {
    final Completer<void> commit = Completer<void>();
    chat.enqueueUploads([
      uploadOf((upload) async {
        _filesUploaded(upload);
        await commit.future;
        upload.onSaving();
      }),
    ]);
    await _waitUntil(() =>
        chat.pendingUploadsOf(_chatId).single.status.value ==
        PendingUploadStatus.committing);
    final PendingUpload upload = chat.pendingUploadsOf(_chatId).single;

    chat.discardUpload(upload);
    expect(chat.pendingUploadsOf(_chatId), [upload],
        reason: 'kayıt yazılıyor: vazgeçilemez');
    expect(upload.isCancelled, isFalse);

    commit.complete();
    await _waitUntil(() => chat.pendingUploadsOf(_chatId).isEmpty);
    expect(chat.pendingUploadsOf(_chatId), isEmpty);
    for (int i = 0; i < 100 && (await _persistedKeys()).isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await _persistedKeys(), isEmpty,
        reason: 'gönderildi: açılışta yeniden gönderilmez');
  });

  test(
      'kayıt yazılamazsa (zaman aşımı) yükleme "gönderilemedi" olur, '
      'kendiliğinden yeniden denenecek; sıra kaydı kalır', () async {
    chat.enqueueUploads([
      uploadOf((upload) async {
        _filesUploaded(upload);
        throw const UploadFailure(PendingUpload.timeoutText);
      }),
    ]);
    await _waitUntil(() =>
        chat.pendingUploadsOf(_chatId).single.status.value ==
        PendingUploadStatus.failed);
    final PendingUpload upload = chat.pendingUploadsOf(_chatId).single;

    expect(upload.errorText, PendingUpload.timeoutText);
    expect(upload.canRetry, isTrue);
    expect(upload.willAutoRetry, isTrue);
    expect(await _persistedKeys(), {upload.persistKey},
        reason: 'uygulama kapanırsa açılışta yeniden denenir');
  });

  test(
      'yeniden denemede yüklemenin anahtarı aynı kalır (sohbet mesajının '
      'kimliği): fotoğraf ikinci kez gönderilmez', () async {
    final List<String> keys = [];
    chat.enqueueUploads([
      uploadOf((upload) async {
        keys.add(upload.persistKey);
        if (keys.length == 1) {
          _filesUploaded(upload);
          throw const UploadFailure(PendingUpload.timeoutText);
        }
      }),
    ]);
    await _waitUntil(() =>
        chat.pendingUploadsOf(_chatId).single.status.value ==
        PendingUploadStatus.failed);

    chat.retryUpload(chat.pendingUploadsOf(_chatId).single);
    await _waitUntil(() => chat.pendingUploadsOf(_chatId).isEmpty);

    expect(keys, hasLength(2));
    expect(keys[1], keys[0]);
    expect(chat.pendingUploadsOf(_chatId), isEmpty);
  });

  test('kayıt yazılırken zaman aşımı sayacı yüklemeyi durdurmaz', () async {
    final PendingUpload upload = uploadOf((upload) async {});
    upload.markUploading();
    _filesUploaded(upload);

    expect(upload.status.value, PendingUploadStatus.committing);
    upload.suspendWatchdog();
    upload.resumeWatchdog();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(upload.timedOut, isFalse);
    expect(upload.isCancelled, isFalse);
  });
}
