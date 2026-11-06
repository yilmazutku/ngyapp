import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/providers/meal_photo_notifications_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String admin = 'admin-1';
  final Object home = Object();

  late FakeFirebaseFirestore db;
  late MealPhotoNotificationsProvider provider;
  late DateTime today;

  setUp(() {
    db = FakeFirebaseFirestore();
    provider = MealPhotoNotificationsProvider(db: db);
    final DateTime now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
  });

  tearDown(() => provider.dispose());

  DocumentReference<Map<String, dynamic>> chat(String id) =>
      db.collection('chats').doc(id);

  Future<void> addMessage(
    String chatId,
    String id, {
    required String senderId,
    required DateTime at,
    bool mealPhoto = true,
    bool deleted = false,
  }) =>
      chat(chatId).collection('messages').doc(id).set({
        'chatId': chatId,
        'senderId': senderId,
        'text': mealPhoto ? 'Öğün: Öğle' : 'Merhaba',
        if (mealPhoto && !deleted) ...{
          'imageUrl': 'https://x/$id.jpg',
          'thumbUrl': 'https://x/${id}_thumb.jpg',
          'storagePath': 'meals/$chatId/lunch',
        },
        if (deleted) 'photoDeleted': true,
        'createdAt': Timestamp.fromDate(at),
      });

  test('bugünkü öğün fotoğrafları, okunma durumu sohbetin okundu işaretinden',
      () async {
    await chat('c1').set({
      'lastMessageAt': Timestamp.fromDate(today.add(const Duration(hours: 12))),
      'adminLastReadAt': {
        admin: Timestamp.fromDate(today.add(const Duration(hours: 10))),
      },
    });
    await addMessage('c1', 'sabah',
        senderId: 'c1', at: today.add(const Duration(hours: 9)));
    await addMessage('c1', 'ogle',
        senderId: 'c1', at: today.add(const Duration(hours: 11)));
    await addMessage('c1', 'yazi',
        senderId: 'c1',
        at: today.add(const Duration(hours: 11, minutes: 30)),
        mealPhoto: false);
    await addMessage('c1', 'silinen',
        senderId: 'c1',
        at: today.add(const Duration(hours: 11, minutes: 40)),
        deleted: true);
    await addMessage('c1', 'dun',
        senderId: 'c1', at: today.subtract(const Duration(hours: 2)));
    await chat('c2').set({
      'lastMessageAt':
          Timestamp.fromDate(today.subtract(const Duration(hours: 3))),
    });
    await addMessage('c2', 'eski',
        senderId: 'c2', at: today.subtract(const Duration(hours: 3)));

    provider.start(admin, owner: home);
    await pumpEventQueue();

    final List<MealPhotoNotification> items = provider.items;
    expect(items.map((i) => i.messageId), ['ogle', 'sabah']);
    expect(items.map((i) => i.isRead), [false, true]);
    expect(items.first.mealLabel, 'Öğle');
    expect(items.first.imageUrl, 'https://x/ogle_thumb.jpg');
    expect(items.first.imageIsOriginal, isFalse);
    expect(provider.unreadCount, 1);

    await chat('c1').update({
      'adminLastReadAt.$admin':
          Timestamp.fromDate(today.add(const Duration(hours: 12))),
    });
    await pumpEventQueue();
    expect(provider.unreadCount, 0);
  });

  test('adminin kendi sohbetindeki ve ofisin gönderdiği fotoğraflar sayılmaz',
      () async {
    await chat(admin).set({'lastMessageAt': Timestamp.fromDate(today)});
    await addMessage(admin, 'kendi',
        senderId: admin, at: today.add(const Duration(minutes: 5)));
    await chat('c3').set({'lastMessageAt': Timestamp.fromDate(today)});
    await addMessage('c3', 'ofis',
        senderId: admin, at: today.add(const Duration(minutes: 6)));

    provider.start(admin, owner: home);
    await pumpEventQueue();
    expect(provider.items, isEmpty);
  });

  test('yeni yüklenen fotoğraf listeye hemen düşer', () async {
    await chat('c1').set({'lastMessageAt': Timestamp.fromDate(today)});
    provider.start(admin, owner: home);
    await pumpEventQueue();
    expect(provider.items, isEmpty);

    await addMessage('c1', 'yeni',
        senderId: 'c1', at: today.add(const Duration(minutes: 1)));
    await pumpEventQueue();
    expect(provider.items.map((i) => i.messageId), ['yeni']);
    expect(provider.unreadCount, 1);
  });
}
