import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;                 // Firestore doc id (filled from snapshot)
  final String chatId;             // e.g., "admin__<uid>" (sorted)
  final String senderId;           // uid
  final String? text;              // null for pure image messages
  final String? imageUrl;          // Firebase Storage download URL
  final String? storagePath;       // Storage path for future cleanup
  final Timestamp? createdAt;      // serverTimestamp()
  final Timestamp? clientCreatedAt;// local fallback for immediate display
  final Map<String, String> reactions; // reactorUid -> emoji (e.g. {adminUid: '👍'})

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.storagePath,
    this.createdAt,
    this.clientCreatedAt,
    this.reactions = const {},
  });

  Map<String, dynamic> toJson() => {
    'chatId': chatId,
    'senderId': senderId,
    if (text != null) 'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (storagePath != null) 'storagePath': storagePath,
    'createdAt': createdAt,           // may be null in memory; on write use serverTimestamp
    if (clientCreatedAt != null) 'clientCreatedAt': clientCreatedAt,
    if (reactions.isNotEmpty) 'reactions': reactions,
  };

  factory MessageModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};
    return MessageModel(
      id: snap.id,
      chatId: (data['chatId'] ?? '') as String,
      senderId: (data['senderId'] ?? '') as String,
      text: data['text'] as String?,
      imageUrl: data['imageUrl'] as String?,
      storagePath: data['storagePath'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      clientCreatedAt: data['clientCreatedAt'] as Timestamp?,
      reactions: _parseReactions(data['reactions']),
    );
  }

  /// Defensively convert the raw Firestore `reactions` field into a
  /// `Map<String, String>` (reactorUid -> emoji).
  static Map<String, String> _parseReactions(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value is String && value.isNotEmpty) {
        out[key] = value;
      }
    });
    return out;
  }
}