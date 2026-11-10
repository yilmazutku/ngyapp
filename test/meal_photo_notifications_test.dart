import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/providers/meal_photo_notifications_provider.dart';

typedef _Filter = Query<Map<String, dynamic>> Function(
    Query<Map<String, dynamic>> query);

class _LiveGroupFirestore extends Fake implements FirebaseFirestore {
  _LiveGroupFirestore(this._inner);

  final FakeFirebaseFirestore _inner;
  int groupQueries = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _inner.collection(collectionPath);

  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionPath) {
    groupQueries++;
    return _LiveGroupQuery(_inner, collectionPath, const []);
  }
}

// ignore: subtype_of_sealed_class
class _LiveGroupQuery extends Fake implements Query<Map<String, dynamic>> {
  _LiveGroupQuery(this._inner, this._collectionId, this._filters);

  final FakeFirebaseFirestore _inner;
  final String _collectionId;
  final List<_Filter> _filters;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) =>
      _LiveGroupQuery(_inner, _collectionId, [
        ..._filters,
        (query) => query.where(
              field,
              isEqualTo: isEqualTo,
              isNotEqualTo: isNotEqualTo,
              isLessThan: isLessThan,
              isLessThanOrEqualTo: isLessThanOrEqualTo,
              isGreaterThan: isGreaterThan,
              isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
              arrayContains: arrayContains,
              arrayContainsAny: arrayContainsAny,
              whereIn: whereIn,
              whereNotIn: whereNotIn,
              isNull: isNull,
            ),
      ]);

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _docs() async {
    Query<Map<String, dynamic>> query = _inner.collectionGroup(_collectionId);
    for (final _Filter filter in _filters) {
      query = filter(query);
    }
    return (await query.get()).docs;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    final List<StreamSubscription<Object?>> triggers = [];
    final Set<String> watchedChats = {};
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> prior = {};
    Future<void> pending = Future<void>.value();
    late final StreamController<QuerySnapshot<Map<String, dynamic>>> controller;

    Future<void> emit() async {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
          await _docs();
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> current = {
        for (final doc in docs) doc.reference.path: doc
      };
      final List<DocumentChange<Map<String, dynamic>>> changes = [
        for (final MapEntry<String,
                QueryDocumentSnapshot<Map<String, dynamic>>> entry
            in current.entries)
          if (!prior.containsKey(entry.key))
            _Change(DocumentChangeType.added, entry.value)
          else if (!mapEquals(prior[entry.key]!.data(), entry.value.data()))
            _Change(DocumentChangeType.modified, entry.value),
        for (final MapEntry<String,
            QueryDocumentSnapshot<Map<String, dynamic>>> entry in prior.entries)
          if (!current.containsKey(entry.key))
            _Change(DocumentChangeType.removed, entry.value),
      ];
      prior = current;
      if (!controller.isClosed) controller.add(_Snapshot(docs, changes));
    }

    void schedule() => pending = pending.then((_) => emit());

    controller = StreamController<QuerySnapshot<Map<String, dynamic>>>(
      onListen: () {
        triggers.add(_inner.collection('chats').snapshots().listen((chats) {
          for (final QueryDocumentSnapshot<Map<String, dynamic>> chat
              in chats.docs) {
            if (!watchedChats.add(chat.id)) continue;
            triggers.add(chat.reference
                .collection(_collectionId)
                .snapshots()
                .listen((_) => schedule()));
          }
          schedule();
        }));
      },
      onCancel: () async {
        for (final StreamSubscription<Object?> trigger in triggers) {
          await trigger.cancel();
        }
      },
    );
    return controller.stream;
  }
}

class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs, this.docChanges);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  final List<DocumentChange<Map<String, dynamic>>> docChanges;
}

class _Change extends Fake implements DocumentChange<Map<String, dynamic>> {
  _Change(this.type, this.doc);

  @override
  final DocumentChangeType type;

  @override
  final DocumentSnapshot<Map<String, dynamic>> doc;
}

class _NoGroupIndexFirestore extends Fake implements FirebaseFirestore {
  _NoGroupIndexFirestore(this._inner);

  final FakeFirebaseFirestore _inner;
  int groupQueries = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _inner.collection(collectionPath);

  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionPath) {
    groupQueries++;
    return _MissingIndexQuery();
  }
}

// ignore: subtype_of_sealed_class
class _MissingIndexQuery extends Fake implements Query<Map<String, dynamic>> {
  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) =>
      this;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      Stream<QuerySnapshot<Map<String, dynamic>>>.error(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'failed-precondition',
        message: 'The query requires an index.',
      ));
}

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

  DocumentReference<Map<String, dynamic>> message(String chatId, String id) =>
      chat(chatId).collection('messages').doc(id);

  Future<void> addMessage(
    String chatId,
    String id, {
    required String senderId,
    required DateTime at,
    bool mealPhoto = true,
    bool deleted = false,
  }) =>
      message(chatId, id).set({
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

  Future<void> markPhotoDeleted(String chatId, String id) =>
      message(chatId, id).update({
        'imageUrl': FieldValue.delete(),
        'thumbUrl': FieldValue.delete(),
        'storagePath': FieldValue.delete(),
        'text': 'Öğün: Öğle (fotoğraf silindi)',
        'photoDeleted': true,
      });

  Future<void> seedReadAndUnreadPhotos() async {
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
  }

  Future<void> expectReadAndUnreadPhotos(
      MealPhotoNotificationsProvider provider) async {
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
  }

  MealPhotoNotificationsProvider providerWith(
    FirebaseFirestore firestore, {
    int maxChatListeners = 0,
  }) {
    final MealPhotoNotificationsProvider created =
        MealPhotoNotificationsProvider(
            db: firestore, maxChatListeners: maxChatListeners);
    addTearDown(created.dispose);
    return created;
  }

  test('bugünkü öğün fotoğrafları, okunma durumu sohbetin okundu işaretinden',
      () async {
    await seedReadAndUnreadPhotos();

    provider.start(admin, owner: home);
    await pumpEventQueue();

    expect(provider.messageListenerCount, 1);
    await expectReadAndUnreadPhotos(provider);
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

  group('tek dinleyici', () {
    late _LiveGroupFirestore live;

    setUp(() => live = _LiveGroupFirestore(db));

    test('sonuç sohbet başına dinlemeyle aynı', () async {
      await seedReadAndUnreadPhotos();
      final MealPhotoNotificationsProvider single = providerWith(live);

      single.start(admin, owner: home);
      await pumpEventQueue();

      expect(live.groupQueries, 1);
      expect(single.messageListenerCount, 1);
      await expectReadAndUnreadPhotos(single);
    });

    test('yeni, silinen fotoğraf ve silinen mesaj hemen yansır', () async {
      await chat('c1').set({'lastMessageAt': Timestamp.fromDate(today)});
      final MealPhotoNotificationsProvider single = providerWith(live);
      single.start(admin, owner: home);
      await pumpEventQueue();
      expect(single.items, isEmpty);

      await addMessage('c1', 'yeni',
          senderId: 'c1', at: today.add(const Duration(minutes: 1)));
      await pumpEventQueue();
      expect(single.items.map((i) => i.messageId), ['yeni']);
      expect(single.unreadCount, 1);

      await markPhotoDeleted('c1', 'yeni');
      await pumpEventQueue();
      expect(single.items, isEmpty);

      await addMessage('c1', 'ikinci',
          senderId: 'c1', at: today.add(const Duration(minutes: 2)));
      await pumpEventQueue();
      expect(single.items.map((i) => i.messageId), ['ikinci']);

      await message('c1', 'ikinci').delete();
      await pumpEventQueue();
      expect(single.items, isEmpty);
      expect(live.groupQueries, 1);
    });

    test('bugünkü listeden çıkıp dönen sohbetin fotoğrafları yine görünür',
        () async {
      await chat('c1').set({'lastMessageAt': Timestamp.fromDate(today)});
      await addMessage('c1', 'bir',
          senderId: 'c1', at: today.add(const Duration(minutes: 1)));
      await chat('c2').set({'lastMessageAt': Timestamp.fromDate(today)});
      await addMessage('c2', 'iki',
          senderId: 'c2', at: today.add(const Duration(minutes: 2)));
      final MealPhotoNotificationsProvider single = providerWith(live);
      single.start(admin, owner: home);
      await pumpEventQueue();
      expect(single.items.map((i) => i.messageId), ['iki', 'bir']);

      await chat('c2').update({
        'lastMessageAt':
            Timestamp.fromDate(today.subtract(const Duration(minutes: 1))),
      });
      await pumpEventQueue();
      expect(single.items.map((i) => i.messageId), ['bir']);

      await chat('c2').update({'lastMessageAt': Timestamp.fromDate(today)});
      await pumpEventQueue();
      expect(single.items.map((i) => i.messageId), ['iki', 'bir']);
    });

    test(
        'bugün etkin olmayan sohbetin ve başka koleksiyonun mesajları sayılmaz',
        () async {
      await chat('c1').set({'lastMessageAt': Timestamp.fromDate(today)});
      await addMessage('c1', 'gecerli',
          senderId: 'c1', at: today.add(const Duration(minutes: 1)));
      await chat('c4').set({
        'lastMessageAt':
            Timestamp.fromDate(today.subtract(const Duration(minutes: 5))),
      });
      await addMessage('c4', 'saati-geri',
          senderId: 'c4', at: today.add(const Duration(minutes: 2)));
      await db
          .collection('destek')
          .doc('c1')
          .collection('messages')
          .doc('x')
          .set({
        'chatId': 'c1',
        'senderId': 'c1',
        'text': 'Öğün: Öğle',
        'imageUrl': 'https://x/x.jpg',
        'storagePath': 'meals/c1/lunch',
        'createdAt': Timestamp.fromDate(today.add(const Duration(minutes: 3))),
      });
      final MealPhotoNotificationsProvider single = providerWith(live);

      single.start(admin, owner: home);
      await pumpEventQueue();
      expect(single.items.map((i) => i.messageId), ['gecerli']);
    });

    test('sınır aşılınca sohbet başına dinleyiciden boşluksuz geçer', () async {
      for (final (String id, int minute) in [('c1', 1), ('c2', 2)]) {
        await chat(id).set({'lastMessageAt': Timestamp.fromDate(today)});
        await addMessage(id, 'foto-$id',
            senderId: id, at: today.add(Duration(minutes: minute)));
      }
      final MealPhotoNotificationsProvider limited =
          providerWith(live, maxChatListeners: 2);
      limited.start(admin, owner: home);
      await pumpEventQueue();
      expect(live.groupQueries, 0);
      expect(limited.messageListenerCount, 2);
      expect(limited.unreadCount, 2);

      final List<int> unreadCounts = [limited.unreadCount];
      limited.addListener(() => unreadCounts.add(limited.unreadCount));

      await addMessage('c3', 'foto-c3',
          senderId: 'c3', at: today.add(const Duration(minutes: 3)));
      await chat('c3').set({'lastMessageAt': Timestamp.fromDate(today)});
      await pumpEventQueue();

      expect(live.groupQueries, 1);
      expect(limited.messageListenerCount, 1);
      expect(limited.items.map((i) => i.messageId),
          ['foto-c3', 'foto-c2', 'foto-c1']);
      for (int i = 1; i < unreadCounts.length; i++) {
        expect(unreadCounts[i], greaterThanOrEqualTo(unreadCounts[i - 1]));
      }

      await addMessage('c1', 'yeni',
          senderId: 'c1', at: today.add(const Duration(minutes: 4)));
      await pumpEventQueue();
      expect(limited.items.first.messageId, 'yeni');
      expect(limited.unreadCount, 4);
    });
  });

  test('tek dinleyici kurulamazsa sohbet başına dinlemeye döner', () async {
    final _NoGroupIndexFirestore noIndex = _NoGroupIndexFirestore(db);
    await seedReadAndUnreadPhotos();
    final MealPhotoNotificationsProvider fallback = providerWith(noIndex);

    fallback.start(admin, owner: home);
    await pumpEventQueue();
    expect(noIndex.groupQueries, 1);
    expect(fallback.hasError, isFalse);
    expect(fallback.messageListenerCount, 1);
    await expectReadAndUnreadPhotos(fallback);

    await chat('c2').set({'lastMessageAt': Timestamp.fromDate(today)});
    await addMessage('c2', 'yeni',
        senderId: 'c2', at: today.add(const Duration(hours: 13)));
    await pumpEventQueue();
    expect(fallback.items.map((i) => i.messageId), ['yeni', 'ogle', 'sabah']);
    expect(fallback.unreadCount, 1);
    expect(fallback.messageListenerCount, 2);
    expect(noIndex.groupQueries, 1);
  });
}
