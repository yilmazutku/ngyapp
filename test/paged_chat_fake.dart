import 'package:cloud_firestore/cloud_firestore.dart';
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
  _FakeAuth(String? uid) : currentUser = uid == null ? null : _FakeUser(uid);

  @override
  final User? currentUser;

  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();
}

class _FakeStorage extends Fake implements FirebaseStorage {}

class PagedFakeChat extends ChatManager {
  PagedFakeChat(FirebaseFirestore db, {String? currentUid})
      : super(db: db, auth: _FakeAuth(currentUid), storage: _FakeStorage());

  int olderPageFailures = 0;
  bool countFails = false;
  int olderPageCalls = 0;
  int countCalls = 0;
  final List<int> olderPageLimits = [];

  Query<Map<String, dynamic>> _newestFirst(String chatId) => db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true);

  static List<MessageData> _toMessages(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) =>
      snapshot.docs.map(MessageData.fromSnapshot).toList();

  @override
  Stream<List<MessageData>> messagesSinceStream(
    String chatId,
    Timestamp since,
  ) =>
      _newestFirst(chatId).snapshots().map(
            (snapshot) => _toMessages(snapshot)
                .where((message) => message.createdAt!.compareTo(since) >= 0)
                .toList(),
          );

  @override
  Future<({List<MessageData> messages, bool fromCache})> fetchOlderPage(
    String chatId,
    Timestamp before, {
    int limit = ChatManager.messagesPageSize,
  }) async {
    olderPageCalls++;
    olderPageLimits.add(limit);
    if (olderPageFailures > 0) {
      olderPageFailures--;
      throw StateError('bağlantı yok');
    }
    return (
      messages: _toMessages(await _newestFirst(chatId).get())
          .where((message) => message.createdAt!.compareTo(before) < 0)
          .take(limit)
          .toList(),
      fromCache: false,
    );
  }

  @override
  Future<int> countImageMessages(String chatId) {
    countCalls++;
    if (countFails) throw StateError('bağlantı yok');
    return super.countImageMessages(chatId);
  }
}

enum ChatSeedKind { photo, text, officeText, officePhoto }

final DateTime _firstMessageAt = DateTime(2026, 10, 1, 8);

Future<void> addChatMessage(
  FirebaseFirestore db,
  String chatId,
  int index,
  ChatSeedKind kind,
) {
  final bool fromOffice =
      kind == ChatSeedKind.officeText || kind == ChatSeedKind.officePhoto;
  final bool hasImage =
      kind == ChatSeedKind.photo || kind == ChatSeedKind.officePhoto;
  final Timestamp at =
      Timestamp.fromDate(_firstMessageAt.add(Duration(minutes: index)));
  return db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .doc('m$index')
      .set({
    'chatId': chatId,
    'senderId': fromOffice ? ChatManager.chatOfficeIds.first : chatId,
    'text': hasImage ? 'Öğün: Öğle' : 'merhaba',
    if (hasImage) 'imageUrl': 'https://x/$index.jpg',
    if (hasImage) 'thumbUrl': 'https://x/${index}_thumb.jpg',
    'createdAt': at,
    'clientCreatedAt': at,
  });
}

Future<void> seedChatMessages(
  FirebaseFirestore db,
  String chatId,
  int count,
  ChatSeedKind Function(int index) kindOf,
) async {
  for (int index = 0; index < count; index++) {
    await addChatMessage(db, chatId, index, kindOf(index));
  }
}

ChatSeedKind alternatingChatKind(int index) => switch (index % 4) {
      0 || 2 => ChatSeedKind.photo,
      1 => ChatSeedKind.text,
      _ => ChatSeedKind.officeText,
    };

Future<void> markChatPhotoDeleted(
  FirebaseFirestore db,
  String chatId,
  String messageId,
) =>
    db.collection('chats').doc(chatId).collection('messages').doc(messageId).update({
      'imageUrl': FieldValue.delete(),
      'thumbUrl': FieldValue.delete(),
      'photoDeleted': true,
    });
