import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/pending_upload.dart';
import 'package:ngy_app/widgets/chat/pending_upload_bubble.dart';

class _FakeSnapshot extends Fake implements TaskSnapshot {
  _FakeSnapshot(this.state, {this.bytesTransferred = 0, this.totalBytes = 0});

  @override
  final TaskState state;
  @override
  final int bytesTransferred;
  @override
  final int totalBytes;
}

class _FakeUploadTask extends Fake implements UploadTask {
  final StreamController<TaskSnapshot> events =
      StreamController<TaskSnapshot>.broadcast();
  TaskSnapshot current = _FakeSnapshot(TaskState.running);
  int cancelCalls = 0;

  @override
  Stream<TaskSnapshot> get snapshotEvents => events.stream;

  @override
  TaskSnapshot get snapshot => current;

  @override
  Future<bool> cancel() async {
    cancelCalls++;
    current = _FakeSnapshot(TaskState.canceled);
    return true;
  }

  void progress(int sent, int total) => events
      .add(_FakeSnapshot(TaskState.running, bytesTransferred: sent, totalBytes: total));
}

PendingUpload _upload({
  Meals meal = Meals.dinner,
  int autoRetries = 0,
  DateTime? createdAt,
}) =>
    PendingUpload(
      chatId: 'danisan1',
      image: XFile('/yok/fotograf.jpg'),
      meal: meal,
      runner: (_) async {},
      autoRetries: autoRetries,
      createdAt: createdAt,
    );

Widget _bubble(PendingUpload upload,
        {VoidCallback? onDiscard, VoidCallback? onRetry}) =>
    MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PendingUploadBubble(
            upload: upload,
            photoSizeOf: (ratio) => Size(220, 220 / ratio),
            bubbleColor: Colors.green.shade50,
            onDiscard: onDiscard ?? () {},
            onRetry: onRetry ?? () {},
          ),
        ),
      ),
    );

const String _autoRetryText =
    'Bağlantı gelince kendiliğinden yeniden denenecek.';

void main() {
  group('Bekleyen yüklemenin sabitleri (B, 3.9)', () {
    test('30 sn ilerlemezse durdurulur, en fazla 5 kez kendiliğinden denenir',
        () {
      expect(PendingUpload.stallTimeout, const Duration(seconds: 30));
      expect(PendingUpload.maxAutoRetries, 5);
    });

    test('zaman aşımı metni senaryodaki gibi', () {
      expect(PendingUpload.timeoutText,
          'Bağlantı yok ya da çok yavaş; fotoğraf gönderilemedi.');
    });
  });

  group('Kendiliğinden yeniden deneme kararı (3.9)', () {
    test('yeni yükleme sırada ve kuyrukta sayılır, yeniden deneme yok', () {
      final PendingUpload upload = _upload();
      expect(upload.status.value, PendingUploadStatus.waiting);
      expect(upload.isQueued, isTrue);
      expect(upload.willAutoRetry, isFalse);

      upload.markUploading();
      expect(upload.status.value, PendingUploadStatus.uploading);
      expect(upload.isQueued, isTrue);
      expect(upload.willAutoRetry, isFalse);
    });

    test('yeniden denenebilir hatada 5. denemeye kadar kendiliğinden denenir', () {
      for (int retries = 0; retries < PendingUpload.maxAutoRetries; retries++) {
        final PendingUpload upload = _upload(autoRetries: retries);
        upload.markFailed(PendingUpload.timeoutText);
        expect(upload.status.value, PendingUploadStatus.failed);
        expect(upload.isQueued, isFalse);
        expect(upload.errorText, PendingUpload.timeoutText);
        expect(upload.willAutoRetry, isTrue, reason: 'autoRetries=$retries');
      }
    });

    test('5 kendiliğinden denemeden sonra artık denenmez', () {
      final PendingUpload upload = _upload(autoRetries: 5);
      upload.markFailed(PendingUpload.timeoutText);
      expect(upload.willAutoRetry, isFalse);
    });

    test('yeniden denenemez hata (ör. sınır dolu) kendiliğinden denenmez', () {
      final PendingUpload upload = _upload();
      upload.markFailed(MealModel.maxImagesReachedMessage, canRetry: false);
      expect(upload.canRetry, isFalse);
      expect(upload.willAutoRetry, isFalse);
    });

    test('kendiliğinden denemeler zincirinde 6. hata artık beklemeye kalır', () {
      PendingUpload upload = _upload();
      int automaticRetries = 0;
      upload.markFailed(PendingUpload.timeoutText);
      while (upload.willAutoRetry) {
        upload = upload.retryCopy(automatic: true);
        automaticRetries++;
        upload.markFailed(PendingUpload.timeoutText);
      }
      expect(automaticRetries, 5);
      expect(upload.autoRetries, 5);
    });

    test('kullanıcının "Tekrar dene"si sayacı sıfırlar; fotoğrafın seçildiği an ve kayıt anahtarı korunur (3.10)',
        () {
      final DateTime picked = DateTime(2026, 10, 13, 8, 15);
      final PendingUpload original =
          _upload(meal: Meals.br, autoRetries: 4, createdAt: picked);
      final PendingUpload automatic = original.retryCopy(automatic: true);
      final PendingUpload manual = automatic.retryCopy();

      expect(automatic.autoRetries, 5);
      expect(manual.autoRetries, 0);
      for (final PendingUpload copy in <PendingUpload>[automatic, manual]) {
        expect(copy.createdAt, picked);
        expect(copy.persistKey, original.persistKey);
        expect(copy.meal, Meals.br);
        expect(copy.image.path, original.image.path);
        expect(copy.id, isNot(original.id));
        expect(copy.status.value, PendingUploadStatus.waiting);
      }
    });

    test('kullanıcı iptal edince yükleme iptal sayılır ve sıra beklemez (3.7)',
        () async {
      final PendingUpload upload = _upload();
      upload.cancel();
      expect(upload.cancelledByUser, isTrue);
      expect(upload.isCancelled, isTrue);
      await upload.aborted.timeout(const Duration(seconds: 1));
    });
  });

  group('30 sn bekçisi (3.9, 3.12)', () {
    testWidgets('30 sn hiç ilerlemeyen yükleme zaman aşımına uğrar ve görev iptal edilir',
        (tester) async {
      final PendingUpload upload = _upload();
      final _FakeUploadTask task = _FakeUploadTask();
      bool aborted = false;
      unawaited(upload.aborted.then((_) => aborted = true));

      upload.markUploading();
      upload.onTask(task);

      await tester.pump(const Duration(seconds: 29));
      expect(upload.timedOut, isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(upload.timedOut, isTrue);
      expect(upload.isCancelled, isTrue);
      expect(aborted, isTrue);
      expect(task.cancelCalls, 1);
      await task.events.close();
    });

    testWidgets('ilerleme geldikçe 30 sn sayacı baştan başlar',
        (tester) async {
      final PendingUpload upload = _upload();
      final _FakeUploadTask task = _FakeUploadTask();
      upload.markUploading();
      upload.onTask(task);

      for (int i = 1; i <= 4; i++) {
        await tester.pump(const Duration(seconds: 20));
        task.progress(i * 100, 1000);
        await tester.pump();
      }
      expect(upload.timedOut, isFalse);
      expect(upload.progress.value, closeTo(0.4, 0.0001));

      await tester.pump(const Duration(seconds: 31));
      expect(upload.timedOut, isTrue);
      await task.events.close();
    });

    testWidgets('uygulama arka plandayken sayaç durur, öne gelince baştan başlar (3.12)',
        (tester) async {
      final PendingUpload upload = _upload();
      final _FakeUploadTask task = _FakeUploadTask();
      upload.markUploading();
      upload.onTask(task);

      await tester.pump(const Duration(seconds: 20));
      upload.suspendWatchdog();
      await tester.pump(const Duration(minutes: 1));
      expect(upload.timedOut, isFalse);

      upload.resumeWatchdog();
      await tester.pump(const Duration(seconds: 29));
      expect(upload.timedOut, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(upload.timedOut, isTrue);
      await task.events.close();
    });
  });

  group('Bekleyen fotoğraf baloncuğu (3.2, 3.4, 3.7, 3.9)', () {
    testWidgets('sıradaki fotoğrafta öğün etiketi, "Sırada" ve "İptal" görünür',
        (tester) async {
      final PendingUpload upload = _upload(meal: Meals.thirdmid);
      int discards = 0;
      await tester.pumpWidget(_bubble(upload, onDiscard: () => discards++));

      expect(find.text('Ara'), findsOneWidget);
      expect(find.text('Sırada'), findsOneWidget);
      expect(find.text('Gönderiliyor…'), findsNothing);
      await tester.tap(find.text('İptal'));
      expect(discards, 1);
    });

    testWidgets('yüklenen fotoğrafta "Gönderiliyor…", ilerleme halkası ve "İptal" görünür',
        (tester) async {
      final PendingUpload upload = _upload(meal: Meals.lunch);
      upload.markUploading();
      upload.progress.value = 0.5;
      await tester.pumpWidget(_bubble(upload));

      expect(find.text('Öğle'), findsOneWidget);
      expect(find.text('Gönderiliyor…'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        0.5,
      );
      expect(find.byTooltip('Gönderimi iptal et'), findsOneWidget);
    });

    testWidgets('bağlantı yokken düşen fotoğrafta hata metni, kendiliğinden deneme notu, "Tekrar dene" ve "Kaldır" görünür',
        (tester) async {
      final PendingUpload upload = _upload(meal: Meals.dinner);
      int retries = 0;
      int discards = 0;
      upload.markFailed(PendingUpload.timeoutText);
      await tester.pumpWidget(_bubble(upload,
          onRetry: () => retries++, onDiscard: () => discards++));

      expect(find.text('Akşam'), findsOneWidget);
      expect(find.text('${PendingUpload.timeoutText} $_autoRetryText'),
          findsOneWidget);
      await tester.tap(find.text('Tekrar dene'));
      await tester.tap(find.text('Kaldır'));
      expect(retries, 1);
      expect(discards, 1);
    });

    testWidgets('5 kendiliğinden denemeden sonra not kalkar, "Tekrar dene" kalır',
        (tester) async {
      final PendingUpload upload = _upload(autoRetries: 5);
      upload.markFailed(PendingUpload.timeoutText);
      await tester.pumpWidget(_bubble(upload));

      expect(find.text(PendingUpload.timeoutText), findsOneWidget);
      expect(find.textContaining(_autoRetryText), findsNothing);
      expect(find.text('Tekrar dene'), findsOneWidget);
    });

    testWidgets('yeniden denenemeyen hatada "Tekrar dene" yok, "Kaldır" var',
        (tester) async {
      final PendingUpload upload = _upload();
      upload.markFailed(MealModel.maxImagesReachedMessage, canRetry: false);
      await tester.pumpWidget(_bubble(upload));

      expect(find.text(MealModel.maxImagesReachedMessage), findsOneWidget);
      expect(find.text('Tekrar dene'), findsNothing);
      expect(find.text('Kaldır'), findsOneWidget);
    });

    testWidgets('mesaj yazılırken bekleyen baloncuk kalkar', (tester) async {
      final PendingUpload upload = _upload();
      upload.markUploading();
      await tester.pumpWidget(_bubble(upload));
      expect(find.text('Gönderiliyor…'), findsOneWidget);

      upload.onSaving();
      await tester.pump();
      expect(find.text('Gönderiliyor…'), findsNothing);
      expect(find.text('Akşam'), findsNothing);
    });

    testWidgets('baloncuk fotoğrafı gerçek oranında gösterir, oran gelince boyut güncellenir',
        (tester) async {
      final PendingUpload upload = _upload();
      await tester.pumpWidget(_bubble(upload));
      final Finder preview = find.byType(ClipRRect).first;
      expect(tester.getSize(preview), const Size(220, 165));

      upload.previewAspectRatio.value = 0.75;
      await tester.pump();
      expect(tester.getSize(preview).height, closeTo(220 / 0.75, 0.01));
    });
  });
}
