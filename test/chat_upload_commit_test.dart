import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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

/// Sıra işlerken Firebase'e dokunulmaz; yalnızca kurucu için.
class _FakeFirestore extends Fake implements FirebaseFirestore {}

/// Oturum değişiklikleri testten verilir ([changes]).
class _FakeAuth extends Fake implements FirebaseAuth {
  final StreamController<User?> changes = StreamController<User?>();

  @override
  Stream<User?> authStateChanges() => changes.stream;
}

class _FakeUser extends Fake implements User {
  _FakeUser(this.uid);

  @override
  final String uid;
}

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

  testWidgets(
      'kayıt aşaması süresi yalnızca öndeyken sayılır; dolunca sonuç '
      '"doğrulanamadı" olur', (tester) async {
    final PendingUpload upload = uploadOf((upload) async {});
    upload.markUploading();
    _filesUploaded(upload);

    await tester.pump(PendingUpload.commitTimeout - const Duration(seconds: 1));
    expect(upload.timedOut, isFalse);

    upload.suspendWatchdog();
    await tester.pump(const Duration(minutes: 10));
    expect(upload.timedOut, isFalse, reason: 'arka plan sayılmaz');

    upload.resumeWatchdog();
    await tester.pump(PendingUpload.commitTimeout - const Duration(seconds: 1));
    expect(upload.timedOut, isFalse, reason: 'öne gelince baştan sayılır');
    await tester.pump(const Duration(seconds: 2));
    expect(upload.timedOut, isTrue);
    expect(upload.commitUnconfirmed, isTrue);
  });

  testWidgets(
      'kayıt süresi dolunca "doğrulanamadı" gösterilir, kaldırılamaz; işlem '
      'sonradan yazarsa baloncuk kalkar', (tester) async {
    // Kendiliğinden yeniden deneme zamanlayıcısı test bitmeden kapansın.
    final ChatManager chat = ChatManager(
      db: _FakeFirestore(),
      auth: _FakeAuth(),
      storage: _FakeStorage(),
    );
    final Completer<void> commit = Completer<void>();
    chat.enqueueUploads([
      uploadOf((upload) async {
        _filesUploaded(upload);
        await commit.future;
        upload.onWritten();
        upload.onSaving();
      }),
    ]);
    await tester.pump();
    final PendingUpload upload = chat.pendingUploadsOf(_chatId).single;
    expect(upload.status.value, PendingUploadStatus.committing);

    await tester.pump(PendingUpload.commitTimeout + const Duration(seconds: 1));
    expect(upload.status.value, PendingUploadStatus.failed);
    expect(upload.errorText, PendingUpload.unconfirmedText);
    expect(upload.commitUnconfirmed, isTrue);
    expect(upload.willAutoRetry, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PendingUploadBubble(
          upload: upload,
          photoSizeOf: (_) => const Size(200, 150),
          onDiscard: () {},
          onRetry: () {},
        ),
      ),
    ));
    expect(find.text('Kaldır'), findsNothing,
        reason: 'gönderilmiş olabilir: kaldırılırsa yine sohbete düşerdi');
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.textContaining(PendingUpload.unconfirmedText), findsOneWidget);

    commit.complete();
    await tester.pump();
    await tester.pump();
    expect(chat.pendingUploadsOf(_chatId), isEmpty,
        reason: 'işlem sonradan yazdı: fotoğraf gönderildi');
    chat.dispose();
  });

  test(
      'açılışta dosyası kalmamış ama gönderilmiş fotoğraf için "yeniden '
      'seçin" denmez; gönderilmemişse denir', () async {
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    await db
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc('gonderildi')
        .set({'imageUrl': 'https://x/a.jpg', 'senderId': _chatId});
    Map<String, Object> entry(String key) => {
          'key': key,
          'chatId': _chatId,
          'path': p.join(temporary.path, 'yok-$key.jpg'),
          'name': 'yok.jpg',
          'meal': Meals.lunch.name,
          'createdAt': DateTime(2026, 10, 22).millisecondsSinceEpoch,
        };
    SharedPreferences.setMockInitialValues({
      _persistedUploadsKey:
          jsonEncode([entry('gonderildi'), entry('gonderilmedi')]),
    });
    final ChatManager restoring = ChatManager(
      db: db,
      auth: _FakeAuth(),
      storage: _FakeStorage(),
    );
    addTearDown(restoring.dispose);

    final ({int restored, int missing}) result =
        await restoring.restorePendingUploads(
      userId: _chatId,
      runner: (upload) async {},
    );

    expect(result.restored, 0);
    expect(result.missing, 1);
    for (int i = 0; i < 100 && (await _persistedKeys()).isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await _persistedKeys(), isEmpty);
  });

  group('oturum', () {
    test(
        'oturum kapanınca bekleyen yüklemeler bu oturumdan çekilir, yeniden '
        'denenmez; sıra kaydı kalır ve sahibi yeniden girince geri yüklenir',
        () async {
      final _FakeAuth auth = _FakeAuth();
      final ChatManager chat = ChatManager(
        db: _FakeFirestore(),
        auth: auth,
        storage: _FakeStorage(),
      );
      addTearDown(chat.dispose);
      auth.changes.add(_FakeUser(_chatId));
      await Future<void>.delayed(Duration.zero);

      int runs = 0;
      chat.enqueueUploads([
        uploadOf((upload) async {
          runs++;
          throw const UploadFailure(PendingUpload.timeoutText);
        }),
      ]);
      await _waitUntil(() =>
          chat.pendingUploadsOf(_chatId).single.status.value ==
          PendingUploadStatus.failed);
      final String key = chat.pendingUploadsOf(_chatId).single.persistKey;

      auth.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(chat.pendingUploadsOf(_chatId), isEmpty,
          reason: 'aynı cihazda giren başka hesap görmesin, yüklemesin');
      chat.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runs, 1, reason: 'oturum yokken yeniden denenmez');
      expect(await _persistedKeys(), {key},
          reason: 'sahibi için cihazda kalır');

      auth.changes.add(_FakeUser(_chatId));
      await Future<void>.delayed(Duration.zero);
      final ({int restored, int missing}) result =
          await chat.restorePendingUploads(
        userId: _chatId,
        runner: (upload) async {},
      );
      expect(result.restored, 1,
          reason: 'aynı uygulama oturumunda yeniden girişte de geri gelir');
      expect(chat.pendingUploadsOf(_chatId).single.persistKey, key);
    });

    test('başka hesaba geçince de çekilir', () async {
      final _FakeAuth auth = _FakeAuth();
      final ChatManager chat = ChatManager(
        db: _FakeFirestore(),
        auth: auth,
        storage: _FakeStorage(),
      );
      addTearDown(chat.dispose);
      auth.changes.add(_FakeUser(_chatId));
      await Future<void>.delayed(Duration.zero);
      final Completer<void> never = Completer<void>();
      chat.enqueueUploads([uploadOf((upload) => never.future)]);
      await _waitUntil(() =>
          chat.pendingUploadsOf(_chatId).single.status.value ==
          PendingUploadStatus.uploading);
      final PendingUpload upload = chat.pendingUploadsOf(_chatId).single;

      auth.changes.add(_FakeUser('admin-1'));
      await Future<void>.delayed(Duration.zero);

      expect(chat.pendingUploadsOf(_chatId), isEmpty);
      expect(upload.released, isTrue);
      expect(upload.isCancelled, isTrue, reason: 'kayıt yazmaz');
    });
  });

  group('sonucu belli olmayan yükleme', () {
    test(
        'yeniden deneme de "belli değil" sayılır: vazgeçilemez, hatası '
        '"doğrulanamadı" olur', () async {
      int attempts = 0;
      chat.enqueueUploads([
        uploadOf((upload) async {
          attempts++;
          if (attempts == 1) {
            throw const UploadFailure(
              PendingUpload.unconfirmedText,
              unconfirmed: true,
            );
          }
          throw const UploadFailure(PendingUpload.defaultErrorText);
        }),
      ]);
      await _waitUntil(() =>
          chat.pendingUploadsOf(_chatId).single.status.value ==
          PendingUploadStatus.failed);
      expect(chat.pendingUploadsOf(_chatId).single.commitUnconfirmed, isTrue);

      chat.retryUpload(chat.pendingUploadsOf(_chatId).single);
      final PendingUpload copy = chat.pendingUploadsOf(_chatId).single;
      expect(copy.commitUnconfirmed, isTrue);
      await _waitUntil(() => attempts == 2 &&
          copy.status.value == PendingUploadStatus.failed);

      expect(copy.errorText, PendingUpload.unconfirmedText);
      chat.discardUpload(copy);
      expect(chat.pendingUploadsOf(_chatId), [copy],
          reason: 'gönderilmiş olabilir: kaldırılamaz');
    });

    testWidgets('belli olmayan yeniden denemede iptal düğmeleri yok',
        (tester) async {
      final PendingUpload copy = PendingUpload(
        chatId: _chatId,
        image: XFile('/yok/foto.jpg'),
        meal: Meals.lunch,
        runner: (_) async {},
        unconfirmed: true,
      )..markUploading();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PendingUploadBubble(
            upload: copy,
            photoSizeOf: (_) => const Size(200, 150),
            onDiscard: () {},
            onRetry: () {},
          ),
        ),
      ));

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('İptal').hitTestable(), findsNothing);
    });

    test('yeniden denenemiyorsa (sınır doldu) kaldırılabilir', () async {
      chat.enqueueUploads([
        uploadOf((upload) async {
          throw const UploadFailure(
            PendingUpload.unconfirmedText,
            unconfirmed: true,
          );
        }),
      ]);
      await _waitUntil(() =>
          chat.pendingUploadsOf(_chatId).single.status.value ==
          PendingUploadStatus.failed);
      chat.retryUpload(chat.pendingUploadsOf(_chatId).single);
      final PendingUpload copy = chat.pendingUploadsOf(_chatId).single;
      copy.markFailed('Sınır doldu', canRetry: false);

      chat.discardUpload(copy);
      expect(chat.pendingUploadsOf(_chatId), isEmpty);
    });
  });

  test(
      'açılışta dosyası duran ama gönderilmiş fotoğraf yeniden yüklenmez, '
      'kaydı silinir', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final File photo = File(p.join(temporary.path, 'gonderildi.jpg'))
      ..writeAsStringSync('photo');
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    await db
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc('gonderildi')
        .set({'imageUrl': 'https://x/a.jpg', 'senderId': _chatId});
    SharedPreferences.setMockInitialValues({
      _persistedUploadsKey: jsonEncode([
        {
          'key': 'gonderildi',
          'chatId': _chatId,
          'path': photo.path,
          'name': 'gonderildi.jpg',
          'meal': Meals.lunch.name,
          'createdAt': DateTime(2026, 10, 22).millisecondsSinceEpoch,
        },
      ]),
    });
    final ChatManager restoring = ChatManager(
      db: db,
      auth: _FakeAuth(),
      storage: _FakeStorage(),
    );
    addTearDown(restoring.dispose);

    final ({int restored, int missing}) result =
        await restoring.restorePendingUploads(
      userId: _chatId,
      runner: (upload) async {},
    );

    expect(result.restored, 0);
    expect(result.missing, 0);
    expect(restoring.pendingUploadsOf(_chatId), isEmpty);
    await _waitUntil(() => !photo.existsSync());
    expect(photo.existsSync(), isFalse);
  });

  test('öğün fotoğraf hakkı: yeniden denenecek başarısız yükleme de sayılır',
      () {
    final PendingUpload upload = uploadOf((_) async {});
    expect(upload.holdsMealSlot, isTrue, reason: 'sırada');
    upload.markFailed('bağlantı yok');
    expect(upload.holdsMealSlot, isTrue, reason: 'yeniden denenecek');
    upload.markFailed('sınır doldu', canRetry: false);
    expect(upload.holdsMealSlot, isFalse);
  });
}
