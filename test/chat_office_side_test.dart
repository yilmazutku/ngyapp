import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';

class _FakeUser extends Fake implements User {
  _FakeUser(this.uid);

  @override
  final String uid;
}

class _FakeAuth extends Fake implements FirebaseAuth {
  _FakeAuth(String uid) : currentUser = _FakeUser(uid);

  @override
  final User? currentUser;

  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();
}

class _FakeStorage extends Fake implements FirebaseStorage {}

void main() {
  const String client = 'danisan-1';
  final String office = ChatManager.chatOfficeIds.first;
  final String clientAdmin =
      ChatManager.adminIds.difference(ChatManager.chatOfficeIds).first;

  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  ChatManager signedIn(String uid) => ChatManager(
        db: db,
        auth: _FakeAuth(uid),
        storage: _FakeStorage(),
      );

  Future<Map<String, dynamic>> summaryOf(String chatId) async =>
      (await db.collection('chats').doc(chatId).get()).data()!;

  group('sohbette ofis tarafı', () {
    test('başkasının sohbetindeki admin ofis tarafındadır', () {
      expect(ChatManager.isOfficeSide(office, client), isTrue);
      expect(ChatManager.isOfficeSide(office, clientAdmin), isTrue);
      expect(ChatManager.isOfficeSide(clientAdmin, client), isTrue);
    });

    test('sohbetin sahibi admin olsa da danışan tarafındadır', () {
      expect(ChatManager.isOfficeSide(client, client), isFalse);
      expect(ChatManager.isOfficeSide(clientAdmin, clientAdmin), isFalse);
    });
  });

  test('danışanın mesajı yalnızca ofisin okunmamışlarına düşer', () async {
    await signedIn(client).sendTextTo(client, 'Merhaba');

    final Map<String, dynamic> summary = await summaryOf(client);
    expect(summary['participants'], [client, ...ChatManager.chatOfficeIds]);
    expect(summary['adminUnreadCount'], {office: 1});
    expect(summary['hasUnreadFor'], [office]);
  });

  group('danışan gibi yazışan admin', () {
    test('kendi sohbetindeki mesajı ofisin okunmamışlarına düşer', () async {
      await signedIn(clientAdmin).sendTextTo(clientAdmin, 'Merhaba');

      final Map<String, dynamic> summary = await summaryOf(clientAdmin);
      expect(summary['participants'],
          [clientAdmin, ...ChatManager.chatOfficeIds]);
      expect(summary['adminUnreadCount'], {office: 1});
      expect(summary['hasUnreadFor'], [office]);
      expect(summary.containsKey('userUnreadCount'), isFalse);
      expect(await signedIn(office).totalUnreadChatsStream().first, 1);
    });

    test('ofisin mesajı onun okunmamışlarına düşer, sohbeti açınca sıfırlanır',
        () async {
      await signedIn(office).sendTextTo(clientAdmin, 'Merhaba');
      final ChatManager own = signedIn(clientAdmin);

      expect(await own.userUnreadCountStream().first, 1);
      expect(await own.currentUserUnreadCount(clientAdmin), 1);
      expect((await summaryOf(clientAdmin))['hasUnreadFor'], [clientAdmin]);

      await own.markChatAsReadForUser(clientAdmin);

      expect(await own.userUnreadCountStream().first, 0);
      expect((await summaryOf(clientAdmin))['hasUnreadFor'], isEmpty);
    });

    test('ofisin sohbet listesi sayacını kullanmaz', () async {
      await signedIn(client).sendTextTo(client, 'Merhaba');

      expect(await signedIn(clientAdmin).totalUnreadChatsStream().first, 0);
    });
  });
}
