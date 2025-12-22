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

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.storagePath,
    this.createdAt,
    this.clientCreatedAt,
  });

  Map<String, dynamic> toJson() => {
    'chatId': chatId,
    'senderId': senderId,
    if (text != null) 'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (storagePath != null) 'storagePath': storagePath,
    'createdAt': createdAt,           // may be null in memory; on write use serverTimestamp
    if (clientCreatedAt != null) 'clientCreatedAt': clientCreatedAt,
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
    );
  }
}