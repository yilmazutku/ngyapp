import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/utils/image_thumbnail.dart';
import 'package:ngy_app/utils/storage_upload.dart';

/// Kayıt işlemi Storage'a dokunmaz; yalnızca adres taşır.
class _FakeRef extends Fake implements Reference {}

/// İşlemin hangi deneme sayısıyla açıldığını kaydeder.
class _RecordingFirestore extends Fake implements FirebaseFirestore {
  _RecordingFirestore(this.inner);

  final FakeFirebaseFirestore inner;
  int? maxAttempts;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    this.maxAttempts = maxAttempts;
    return inner.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

const String _uid = 'danisan-1';
const String _day = '2026-10-22';
const String _messageId = '1729500000000000_0';

UploadedImage _image(String name) => UploadedImage(
      ref: _FakeRef(),
      url: 'https://x/$name.jpg',
      thumbRef: _FakeRef(),
      thumbUrl: 'https://x/${name}_thumb.jpg',
      thumbBytes: null,
      size: const ImagePixelSize(1600, 1200),
    );

void main() {
  late FakeFirebaseFirestore db;
  late DocumentReference<Map<String, dynamic>> dayDoc;
  late DocumentReference<Map<String, dynamic>> mealDoc;
  late DocumentReference<Map<String, dynamic>> chatDoc;
  late DocumentReference<Map<String, dynamic>> messageDoc;
  final DateTime sentAt = DateTime(2026, 10, 22, 12, 30);

  setUp(() {
    db = FakeFirebaseFirestore();
    dayDoc = db.collection('users').doc(_uid).collection('meals').doc(_day);
    mealDoc = dayDoc.collection('mealEntries').doc(Meals.lunch.name);
    chatDoc = db.collection('chats').doc(_uid);
    messageDoc = chatDoc.collection('messages').doc(_messageId);
  });

  Future<MealImageWrite> write(
    UploadedImage image, {
    bool toChat = true,
    bool cancelsReminder = true,
    bool abandoned = false,
  }) =>
      MealManager.writeMealImage(
        db,
        mealDoc,
        userId: _uid,
        meal: Meals.lunch,
        subscriptionId: _uid,
        image: image,
        time: sentAt,
        cancelsReminder: cancelsReminder,
        messageRef: toChat ? messageDoc : null,
        abandoned: () => abandoned,
      );

  Future<List<String>> mealUrls() async {
    final snapshot = await mealDoc.get();
    return snapshot.exists
        ? MealModel.fromDocument(snapshot).imageUrls
        : const <String>[];
  }

  Future<int> messageCount() async =>
      (await chatDoc.collection('messages').get()).docs.length;

  group('sohbetten gönderilen öğün fotoğrafı', () {
    test('öğün kaydı, gün işareti, sohbet özeti ve mesaj birlikte yazılır',
        () async {
      final UploadedImage image = _image('a');
      final MealImageWrite result = await write(image);

      expect(result.kind, MealImageWriteKind.written);
      expect(result.postedImageUrl, image.url);
      expect(await mealUrls(), [image.url]);

      final Map<String, dynamic> day = (await dayDoc.get()).data()!;
      expect(day['meals'], {Meals.lunch.name: true});
      expect(day['reminderCancelled'], {Meals.lunch.name: true});

      final Map<String, dynamic> message = (await messageDoc.get()).data()!;
      expect(message['chatId'], _uid);
      expect(message['senderId'], _uid);
      expect(message['text'], Meals.lunch.chatCaption);
      expect(message['imageUrl'], image.url);
      expect(message['thumbUrl'], image.thumbUrl);
      expect(message['imageWidth'], 1600);
      expect(message['imageHeight'], 1200);
      expect(message['storagePath'],
          '${Meals.chatMarkerPrefix}$_uid/${Meals.lunch.name}');
      expect(message['createdAt'], isNotNull);

      final Map<String, dynamic> summary = (await chatDoc.get()).data()!;
      expect(summary['lastMessage'], Meals.lunch.chatSummary);
      expect(summary['lastImageUrl'], image.url);
      expect(summary['participants'], [_uid, ...ChatManager.chatOfficeIds]);
      for (final String admin in ChatManager.chatOfficeIds) {
        expect(summary['adminUnreadCount'][admin], 1);
        expect(summary['hasUnreadFor'], contains(admin));
      }
      for (final String admin
          in ChatManager.adminIds.difference(ChatManager.chatOfficeIds)) {
        expect(summary['adminUnreadCount'][admin], isNull);
        expect(summary['hasUnreadFor'], isNot(contains(admin)));
      }
    });

    test(
        'yeniden deneme (yeni dosya, aynı yükleme) ikinci kez yazmaz: önceki '
        'fotoğrafı bildirir', () async {
      final UploadedImage first = _image('a');
      await write(first);

      final MealImageWrite retry = await write(_image('a-retry'));

      expect(retry.kind, MealImageWriteKind.alreadyPosted);
      expect(retry.postedImageUrl, first.url,
          reason: 'yeniden denemenin dosyası silinsin, öncekininki kalsın');
      expect(await mealUrls(), [first.url]);
      expect(await messageCount(), 1);
      final Map<String, dynamic> summary = (await chatDoc.get()).data()!;
      for (final String admin in ChatManager.chatOfficeIds) {
        expect(summary['adminUnreadCount'][admin], 1,
            reason: 'okunmamış sayısı iki kez artmaz');
      }
    });

    test(
        'aynı deneme yeniden çalışırsa (yanıt kayboldu) dosyası korunur, bir '
        'şey yazılmaz', () async {
      final UploadedImage image = _image('a');
      await write(image);

      final MealImageWrite rerun = await write(image);

      expect(rerun.kind, MealImageWriteKind.alreadyPosted);
      expect(rerun.postedImageUrl, image.url,
          reason: 'adres aynı: dosya silinmemeli');
      expect(await mealUrls(), [image.url]);
      expect(await messageCount(), 1);
    });

    test('mesaj fotoğrafı sonradan silindiyse yeniden deneme yine yazmaz',
        () async {
      await write(_image('a'));
      await messageDoc.update({
        'imageUrl': FieldValue.delete(),
        'photoDeleted': true,
      });

      final MealImageWrite retry = await write(_image('a-retry'));

      expect(retry.kind, MealImageWriteKind.alreadyPosted);
      expect(retry.postedImageUrl, isNull,
          reason: 'yeniden denemenin dosyası silinsin');
      expect(await messageCount(), 1);
    });

    test('farklı yüklemeler (farklı anahtar) ayrı ayrı yazılır', () async {
      await write(_image('a'));
      messageDoc = chatDoc.collection('messages').doc('1729500000000001_1');
      final MealImageWrite second = await write(_image('b'));

      expect(second.kind, MealImageWriteKind.written);
      expect(await mealUrls(), ['https://x/a.jpg', 'https://x/b.jpg']);
      expect(await messageCount(), 2);
      // Okunmamış sayısının 2 olması burada denenmez: sahte Firestore
      // birleştirilen iç içe alandaki artırmayı uygulamıyor (Firestore
      // emülatöründe 2 olduğu denendi).
    });

    test('öğünün fotoğraf sınırı doluysa hiçbir şey yazılmaz', () async {
      await mealDoc.set(MealModel(
        mealId: Meals.lunch.name,
        mealType: Meals.lunch,
        imageUrls: [
          for (int i = 0; i < MealModel.maxImages; i++) 'https://x/u$i.jpg',
        ],
        timestamp: sentAt,
        isChecked: true,
      ).toMap());

      final MealImageWrite result = await write(_image('fazla'));

      expect(result.kind, MealImageWriteKind.limitReached);
      expect((await messageDoc.get()).exists, isFalse);
      expect((await chatDoc.get()).exists, isFalse);
      expect((await dayDoc.get()).exists, isFalse);
      expect(await mealUrls(), hasLength(MealModel.maxImages));
    });
  });

  group('süresi dolan deneme (bekleyen artık beklemiyor)', () {
    test('işlem yeniden çalışsa da yazmaz', () async {
      await expectLater(
        write(_image('a'), abandoned: true),
        throwsA(isA<UploadCancelledException>()),
      );

      expect((await messageDoc.get()).exists, isFalse);
      expect((await chatDoc.get()).exists, isFalse);
      expect((await dayDoc.get()).exists, isFalse);
      expect(await mealUrls(), isEmpty);
    });

    test('ama önceki deneme yazdıysa yine "gönderildi" der', () async {
      final UploadedImage image = _image('a');
      await write(image);

      final MealImageWrite rerun = await write(image, abandoned: true);

      expect(rerun.kind, MealImageWriteKind.alreadyPosted);
      expect(rerun.postedImageUrl, image.url);
    });
  });

  group('eklentinin kendi yeniden denemeleri', () {
    Future<int?> attemptsOf({required bool toChat}) async {
      final _RecordingFirestore recording = _RecordingFirestore(db);
      await MealManager.writeMealImage(
        recording,
        mealDoc,
        userId: _uid,
        meal: Meals.lunch,
        subscriptionId: _uid,
        image: _image('a'),
        time: sentAt,
        cancelsReminder: toChat,
        messageRef: toChat ? messageDoc : null,
      );
      return recording.maxAttempts;
    }

    test('sohbet yazımında kapalı: yeniden denemeyi sıra yapar', () async {
      expect(await attemptsOf(toChat: true), 1);
    });

    test(
        'sohbetsiz yazımda açık: danışanın aynı anki yazımıyla çakışınca '
        'admin yüklemesi hata vermez', () async {
      expect(await attemptsOf(toChat: false), greaterThan(1));
    });
  });

  group('sohbetsiz yükleme (admin test verisi, admin fotoğraf ekleme)', () {
    test('yalnızca öğün kaydı ve gün işareti yazılır; hatırlatma kapanmaz',
        () async {
      final UploadedImage image = _image('admin');
      final MealImageWrite result =
          await write(image, toChat: false, cancelsReminder: false);

      expect(result.kind, MealImageWriteKind.written);
      expect(await mealUrls(), [image.url]);
      final Map<String, dynamic> day = (await dayDoc.get()).data()!;
      expect(day['meals'], {Meals.lunch.name: true});
      expect(day.containsKey('reminderCancelled'), isFalse);
      expect((await chatDoc.get()).exists, isFalse);
      expect(await messageCount(), 0);
    });

    test('aynı adres yeniden yazılmaz', () async {
      final UploadedImage image = _image('admin');
      await write(image, toChat: false);

      final MealImageWrite rerun = await write(image, toChat: false);

      expect(rerun.kind, MealImageWriteKind.alreadyPosted);
      expect(await mealUrls(), [image.url]);
    });
  });
}
