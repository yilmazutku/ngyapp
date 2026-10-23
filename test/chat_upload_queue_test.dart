import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/pending_upload.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/utils/storage_upload.dart';
import 'package:ngy_app/widgets/chat/pending_upload_bubble.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Her çağrıda hata verir: sohbet mesajı okunamaz (bkz.
/// `ChatManager._isMealPhotoPosted`).
class _UnreadableFirestore extends Fake implements FirebaseFirestore {}

/// Oturum hiç değişmez (bkz. `ChatManager._onAuthChanged`).
class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();
}

class _FakeStorage extends Fake implements FirebaseStorage {}

class _FakeRef extends Fake implements Reference {}

const MethodChannel _pathProvider =
    MethodChannel('plugins.flutter.io/path_provider');
const String _chatId = 'user-1';
const String _persistedUploadsKey = 'chat_pending_meal_uploads_v1';
const String _autoRetryNote = 'kendiliğinden yeniden denenecek';

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
  return {
    for (final Object? entry in jsonDecode(raw) as List)
      if (entry is Map) entry['key'] as String,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('chat_upload_queue_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async => temporary.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    temporary.deleteSync(recursive: true);
  });

  ChatManager newChat({FirebaseFirestore? db}) => ChatManager(
        db: db ?? FakeFirebaseFirestore(),
        auth: _FakeAuth(),
        storage: _FakeStorage(),
      );

  PendingUpload uploadOf(
    Future<void> Function(PendingUpload upload) runner, {
    String chatId = _chatId,
  }) {
    final File file = File(p.join(temporary.path, '$chatId.jpg'))
      ..writeAsStringSync('photo');
    return PendingUpload(
      chatId: chatId,
      image: XFile(file.path),
      meal: Meals.lunch,
      runner: runner,
    );
  }

  PendingUpload bare() => PendingUpload(
        chatId: 'c1',
        image: XFile('/yok/foto.jpg'),
        meal: Meals.lunch,
        runner: (_) async {},
      );

  Future<void> pumpBubble(WidgetTester tester, PendingUpload upload) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PendingUploadBubble(
            upload: upload,
            photoSizeOf: (_) => const Size(200, 150),
            onDiscard: () {},
            onRetry: () {},
          ),
        ),
      ));

  group('PendingUpload', () {
    test('kayıtlar yazılınca sırada sayılmaz (öğün kaydında zaten var)', () {
      final PendingUpload u = bare()..markUploading();
      _filesUploaded(u);
      expect(u.isQueued, isTrue);
      expect(u.holdsMealSlot, isTrue);

      u.onWritten();
      expect(u.status.value, PendingUploadStatus.committing,
          reason: 'mesajın sohbete gelmesi bekleniyor');
      expect(u.isQueued, isFalse,
          reason: 'kalan hak hesabında iki kez sayılmaz');
      expect(u.holdsMealSlot, isFalse);
    });

    testWidgets('kayıtlar yazılınca kayıt sayacı durur', (tester) async {
      final PendingUpload u = bare()..markUploading();
      _filesUploaded(u);
      await tester
          .pump(PendingUpload.commitTimeout - const Duration(seconds: 1));

      u.onWritten();
      await tester.pump(const Duration(seconds: 10));
      expect(u.timedOut, isFalse,
          reason: 'yazıldı: mesaj beklenirken "gönderilemedi" denmez');
    });

    test('tekrar denenemeyen hata kendiliğinden de denenmez', () {
      final PendingUpload u = bare()
        ..markFailed(MealModel.maxImagesReachedMessage, canRetry: false);
      expect(u.willAutoRetry, isFalse);
    });
  });

  group('PendingUploadBubble', () {
    testWidgets('kayıt aşamasında baloncuğun boyu değişmez', (tester) async {
      final PendingUpload u = bare()..markUploading();
      await pumpBubble(tester, u);
      Size bubbleSize() => tester.getSize(find
          .descendant(
              of: find.byType(PendingUploadBubble),
              matching: find.byType(Container))
          .first);
      final Size uploading = bubbleSize();

      u.status.value = PendingUploadStatus.committing;
      await tester.pump();
      expect(bubbleSize(), uploading);
    });

    testWidgets('kendiliğinden deneme notu yalnızca denenecekse görünür',
        (tester) async {
      await pumpBubble(tester, bare()..markFailed(PendingUpload.timeoutText));
      expect(find.textContaining(_autoRetryNote), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);

      await pumpBubble(
          tester,
          bare()
            ..markFailed(MealModel.maxImagesReachedMessage, canRetry: false));
      expect(find.textContaining(_autoRetryNote), findsNothing);
      expect(find.text('Tekrar dene'), findsNothing);
      expect(find.text('Kaldır'), findsOneWidget);
    });
  });

  group('ChatManager', () {
    testWidgets(
        'arka plandan dönünce kayıt sayacı baştan başlar, dolunca '
        '"doğrulanamadı" olur', (tester) async {
      final ChatManager chat = newChat();
      try {
        chat.enqueueUploads([
          uploadOf((upload) async {
            _filesUploaded(upload);
            await Completer<void>().future;
          }),
        ]);
        await tester.pump();
        final PendingUpload u = chat.pendingUploadsOf(_chatId).single;
        expect(u.status.value, PendingUploadStatus.committing);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(minutes: 10));
        expect(u.status.value, PendingUploadStatus.committing);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester
            .pump(PendingUpload.commitTimeout + const Duration(seconds: 1));
        expect(u.status.value, PendingUploadStatus.failed,
            reason: 'sayaç öne gelince yeniden kurulmalı');
        expect(u.errorText, PendingUpload.unconfirmedText);
      } finally {
        chat.dispose();
      }
    });

    testWidgets('arka plandayken sıraya eklenen fotoğrafın süresi sayılmaz',
        (tester) async {
      final ChatManager chat = newChat();
      try {
        // İlk yükleme yaşam döngüsü izlemesini başlatır.
        chat.enqueueUploads([uploadOf((_) async {}, chatId: 'baska')]);
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        chat.enqueueUploads([
          uploadOf((upload) async {
            _filesUploaded(upload);
            await Completer<void>().future;
          }),
        ]);
        await tester.pump(const Duration(minutes: 10));
        final PendingUpload u = chat.pendingUploadsOf(_chatId).single;
        expect(u.status.value, PendingUploadStatus.committing,
            reason: 'arka plan sayılmaz');

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester
            .pump(PendingUpload.commitTimeout + const Duration(seconds: 1));
        expect(u.status.value, PendingUploadStatus.failed);
      } finally {
        chat.dispose();
      }
    });

    test('mesaj yazılıp göründüğünde sıra kaydı, işlem bitmeden silinir',
        () async {
      final ChatManager chat = newChat();
      addTearDown(chat.dispose);
      final Completer<void> tail = Completer<void>();
      chat.enqueueUploads([
        uploadOf((upload) async {
          _filesUploaded(upload);
          upload.onWritten();
          upload.onSaving();
          await tail.future;
        }),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await _persistedKeys(), isEmpty,
          reason: 'uygulama şimdi kapansa da açılışta yeniden gönderilmez');
      tail.complete();
    });

    test(
        'açılışta mesaj okunamazsa sıra kaydı kalır, "yeniden seçin" '
        'denmez', () async {
      SharedPreferences.setMockInitialValues({
        _persistedUploadsKey: jsonEncode([
          {
            'key': 'okunamadi',
            'chatId': _chatId,
            'path': p.join(temporary.path, 'yok.jpg'),
            'name': 'yok.jpg',
            'meal': Meals.lunch.name,
            'createdAt': DateTime(2026, 10, 22).millisecondsSinceEpoch,
          },
        ]),
      });
      final ChatManager restoring = newChat(db: _UnreadableFirestore());
      addTearDown(restoring.dispose);

      final ({int restored, int missing}) result = await restoring
          .restorePendingUploads(userId: _chatId, runner: (_) async {});

      expect(result.restored, 0);
      expect(result.missing, 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await _persistedKeys(), {'okunamadi'},
          reason: 'sonraki açılışta yeniden bakılır');
    });

    testWidgets(
        'süresi dolan deneme yazmadan biterse yükleme "gönderilemedi" kalır',
        (tester) async {
      final ChatManager chat = newChat();
      try {
        final Completer<void> commit = Completer<void>();
        chat.enqueueUploads([
          uploadOf((upload) async {
            _filesUploaded(upload);
            await commit.future;
          }),
        ]);
        await tester.pump();
        final PendingUpload u = chat.pendingUploadsOf(_chatId).single;
        await tester
            .pump(PendingUpload.commitTimeout + const Duration(seconds: 1));
        expect(u.status.value, PendingUploadStatus.failed);

        commit.complete();
        await tester.pump();
        await tester.pump();
        expect(chat.pendingUploadsOf(_chatId), [u]);
      } finally {
        chat.dispose();
      }
    });
  });
}
