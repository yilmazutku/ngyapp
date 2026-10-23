import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/pending_upload.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Sıra işlerken Firebase'e dokunulmaz; yalnızca kurucu için.
class _FakeFirestore extends Fake implements FirebaseFirestore {}

/// Oturum hiç değişmez.
class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();
}

class _FakeStorage extends Fake implements FirebaseStorage {}

const MethodChannel _pathProvider =
    MethodChannel('plugins.flutter.io/path_provider');

const String _chatId = 'user-1';

/// Sıranın cihazda saklandığı anahtar (bkz. ChatManager).
const String _persistedUploadsKey = 'chat_pending_meal_uploads_v1';

/// Silinmemesi beklenen dosyalar için bekleme: silme beklenmeden başlar.
const Duration _settle = Duration(milliseconds: 300);

Future<void> _waitUntil(bool Function() condition) async {
  for (int i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late ChatManager chat;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('chat_upload_files_test');
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
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    temporary.deleteSync(recursive: true);
  });

  File photoFile([String name = 'photo.jpg']) =>
      File(p.join(temporary.path, name))..writeAsStringSync('photo');

  PendingUpload uploadOf(
    File file,
    Future<void> Function(PendingUpload upload) runner,
  ) =>
      PendingUpload(
        chatId: _chatId,
        image: XFile(file.path),
        meal: Meals.lunch,
        runner: runner,
      );

  for (final TargetPlatform platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    group('$platform', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test('yüklenince dosya, baloncuk kalktıktan sonra silinir', () async {
        final File file = photoFile();
        // Baloncuk sıradan kalktığında dosya hâlâ durmalı.
        bool? existedWhenRemoved;
        chat.addListener(() {
          if (existedWhenRemoved == null &&
              chat.pendingUploadsOf(_chatId).isEmpty) {
            existedWhenRemoved = file.existsSync();
          }
        });

        chat.enqueueUploads([uploadOf(file, (upload) async {})]);
        await _waitUntil(() => !file.existsSync());

        expect(existedWhenRemoved, isTrue);
        expect(chat.pendingUploadsOf(_chatId), isEmpty);
        expect(file.existsSync(), isFalse);
      });

      test('yüklenemeyince dosya kalır, yeniden denemede yüklenince silinir',
          () async {
        final File file = photoFile();
        int attempts = 0;
        chat.enqueueUploads([
          uploadOf(file, (upload) async {
            if (attempts++ == 0) throw const UploadFailure('bağlantı yok');
          }),
        ]);
        await _waitUntil(() =>
            chat.pendingUploadsOf(_chatId).single.status.value ==
            PendingUploadStatus.failed);
        await Future<void>.delayed(_settle);
        expect(file.existsSync(), isTrue);

        chat.retryUpload(chat.pendingUploadsOf(_chatId).single);
        await _waitUntil(() => !file.existsSync());
        expect(attempts, 2);
        expect(chat.pendingUploadsOf(_chatId), isEmpty);
        expect(file.existsSync(), isFalse);
      });

      test('yüklenemeyen fotoğraf kaldırılınca dosyası silinir', () async {
        final File file = photoFile();
        chat.enqueueUploads([
          uploadOf(file, (upload) async {
            throw const UploadFailure('bağlantı yok');
          }),
        ]);
        await _waitUntil(() =>
            chat.pendingUploadsOf(_chatId).single.status.value ==
            PendingUploadStatus.failed);

        chat.discardUpload(chat.pendingUploadsOf(_chatId).single);
        expect(chat.pendingUploadsOf(_chatId), isEmpty);
        expect(file.existsSync(), isTrue);
        await _waitUntil(() => !file.existsSync());
        expect(file.existsSync(), isFalse);
      });

      test('yüklenirken iptal edilince dosyası silinir', () async {
        final File file = photoFile();
        final Completer<void> started = Completer<void>();
        chat.enqueueUploads([
          uploadOf(file, (upload) async {
            started.complete();
            await Completer<void>().future;
          }),
        ]);
        await started.future;

        chat.discardUpload(chat.pendingUploadsOf(_chatId).single);
        await _waitUntil(() => !file.existsSync());
        expect(chat.pendingUploadsOf(_chatId), isEmpty);
        expect(file.existsSync(), isFalse);
      });

      test('açılışta düzenleme klasöründeki eski, sırada olmayan dosyalar '
          'silinir', () async {
        final Directory photoEdit =
            Directory(p.join(temporary.path, 'photo_edit'))..createSync();
        final DateTime old = DateTime.now().subtract(const Duration(days: 3));
        File editFile(String name) =>
            File(p.join(photoEdit.path, name))..writeAsStringSync('photo');
        final File stale = editFile('stale.jpg')..setLastModifiedSync(old);
        final File queued = editFile('queued.jpg')..setLastModifiedSync(old);
        final File fresh = editFile('fresh.jpg');
        // Başka bir kullanıcının sırasındaki fotoğraf: geri yüklenmez ama
        // dosyası silinmez.
        SharedPreferences.setMockInitialValues({
          _persistedUploadsKey: jsonEncode([
            {
              'key': 'k1',
              'chatId': 'user-2',
              'path': queued.path,
              'name': 'queued.jpg',
              'meal': Meals.lunch.name,
              'createdAt': old.millisecondsSinceEpoch,
            },
          ]),
        });

        final ({int restored, int missing}) result =
            await chat.restorePendingUploads(
          userId: _chatId,
          runner: (upload) async {},
        );
        await _waitUntil(() => !stale.existsSync());

        expect(result.restored, 0);
        expect(stale.existsSync(), isFalse);
        expect(queued.existsSync(), isTrue);
        expect(fresh.existsSync(), isTrue);
      });
    });
  }

  test('masaüstünde yüklenen fotoğrafın dosyası silinmez', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final File file = photoFile();
    chat.enqueueUploads([uploadOf(file, (upload) async {})]);
    await _waitUntil(() => chat.pendingUploadsOf(_chatId).isEmpty);
    await Future<void>.delayed(_settle);
    expect(file.existsSync(), isTrue);
  });
}
