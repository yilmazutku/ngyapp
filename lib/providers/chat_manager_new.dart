// lib/providers/chat_manager_new.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

/// Data Transfer Object representing a chat message from Firestore.
/// 
/// Structure:
/// - id: Firestore document ID
/// - chatId: The chat identifier (equals user UID in our one-chat-per-user model)
/// - senderId: UID of the user who sent the message
/// - text: Optional text content (null for image-only messages)
/// - imageUrl: Optional Firebase Storage download URL for images
/// - storagePath: Optional Storage path for cleanup operations
/// - createdAt: Server-side timestamp (authoritative)
/// - clientCreatedAt: Client-side timestamp (fallback while server timestamp is pending)
/// - reactions: Map of reactorUid -> emoji (e.g. {adminUid: '👍'}). Empty when no
///   one has reacted. Only one reaction per person is kept (WhatsApp-style).
class MessageData {
  final String id;
  final String chatId; //chatId if provided (admin viewing another user), otherwise current user's UID
  final String senderId;
  final String? text;
  final String? imageUrl;
  final String? storagePath;
  final Timestamp? createdAt;
  final Timestamp? clientCreatedAt;

  /// Reactions left on this message, keyed by the reactor's UID.
  /// The value is the reaction emoji (e.g. '👍' or '❤️').
  final Map<String, String> reactions;

  MessageData({
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

  /// Factory constructor to create a MessageData instance from a Firestore snapshot.
  factory MessageData.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};
    return MessageData(
      id: snap.id,
      chatId: (data['chatId'] ?? '') as String,
      senderId: (data['senderId'] ?? '') as String,
      text: data['text'] as String?,
      imageUrl: data['imageUrl'] as String?,
      storagePath: data['storagePath'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      clientCreatedAt: data['clientCreatedAt'] as Timestamp?,
      reactions: parseReactions(data['reactions']),
    );
  }

  /// Safely convert the raw Firestore `reactions` field into a
  /// `Map<String, String>`. Firestore may hand us a `Map<Object?, Object?>`,
  /// so we defensively filter to string keys and non-empty string values.
  static Map<String, String> parseReactions(dynamic raw) {
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

/// Enum to distinguish between different types of upload operations.
/// Used for UI feedback and progress tracking.
enum UploadKind { 
  chatImage,  // Regular chat image upload
  mealImage   // Meal-specific image upload
}

/// ChatManager handles all chat-related operations including:
/// - Sending text messages
/// - Sending images with compression and progress tracking
/// - Uploading meal photos
/// - Managing chat document structure
/// 
/// Architecture:
/// - One chat per user: chatId == userUid
/// - Collection structure: chats/{userUid}/messages/*
/// - The admin UID is automatically added as a participant in every chat
/// - Supports admin viewing any user's chat
/// 
/// Admin UID:
/// - Nilay: 0MvvbZsjbmNPW4QYShRNSOOtkE43
class ChatManager extends ChangeNotifier {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final FirebaseStorage storage;
  
  /// Maximum allowed image size: 5MB
  final MAX_IMG_SIZE = 5 * 1024 * 1024;
  
  /// Admin user IDs - these users have elevated permissions and are participants in all chats
  static const Set<String> adminIds = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    'SdPI69ChOvepuq9HrlW6no9rMRn1', // Admin
  };

  /// Check if a given UID belongs to an admin user
  static bool isAdminUid(String uid) => adminIds.contains(uid);

  /// Get admin IDs set (for external access)
  static Set<String> get adminUids => adminIds;

  ChatManager({
    required this.db,
    required this.auth,
    required this.storage,
  });

  // ===== UI Controllers =====
  // These controllers are owned and managed by ChatManager for lifecycle consistency
  
  /// Text input controller for the message input field
  final TextEditingController messageController = TextEditingController();
  
  /// Scroll controller for the message list - shared between Scrollbar and ListView
  final ScrollController scrollController = ScrollController();

  // ===== State Management =====
  
  /// Indicates if a text message send operation is in progress
  bool _sending = false;
  bool get sending => _sending;

  /// Active Firebase Storage upload task (null when no upload is in progress)
  UploadTask? _activeTask;
  
  /// Upload progress: 0.0-1.0 for actual upload, null during compression phase
  double? _uploadProgress;
  
  /// Type of upload currently in progress (chatImage or mealImage)
  UploadKind? _uploadKind;

  /// True if an image upload is currently in progress
  bool get isUploading => _activeTask != null;
  
  /// Current upload progress (0.0-1.0) or null if indeterminate
  double? get uploadProgress => _uploadProgress;
  
  /// Type of upload currently in progress
  UploadKind? get uploadKind => _uploadKind;

  /// Current authenticated user's UID
  String get userId => auth.currentUser!.uid;

  /// Returns the chat ID for a given user UID.
  /// In our one-chat-per-user model, chatId equals the user's UID.
  String chatIdForUser(String uid) {
    return uid;
  }

  // ===== Firestore References =====
  
  /// Returns a reference to the chat document for a given chatId
  DocumentReference<Map<String, dynamic>> _chatDoc(String chatId) =>
      db.collection('chats').doc(chatId);

  /// Returns a query for messages in a specific chat, ordered by creation time (newest first)
  /// Limited to 50 most recent messages for performance
  Query<Map<String, dynamic>> _messagesQuery(String chatId) => _chatDoc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(50);

  /// Returns a stream of messages for a specific chat.
  /// Messages are ordered newest-first and limited to 50.
  ///
  /// Usage: Used by UI to reactively display messages.
  Stream<List<MessageData>> messagesStreamFor(String chatId) {
    return _messagesQuery(chatId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MessageData.fromSnapshot(d)).toList());
  }

  /// Returns a live stream of every photo the *user* (chatId == userId) has
  /// uploaded to their chat, newest first.
  ///
  /// Includes both direct chat images and meal photos, since both are stored as
  /// messages with `senderId == userId` and a non-empty `imageUrl`. The admin's
  /// own uploaded images are intentionally excluded.
  ///
  /// Implementation note: this filters by `senderId` only — a single-field
  /// equality that Firestore indexes automatically — and sorts client-side, so
  /// it needs NO composite index (unlike the ordered [_messagesQuery]).
  Stream<List<MessageData>> userUploadedImagesStream(String userId) {
    return _chatDoc(userId)
        .collection('messages')
        .where('senderId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final images = snap.docs
          .map((d) => MessageData.fromSnapshot(d))
          .where((m) => (m.imageUrl ?? '').isNotEmpty)
          .toList();

      // Newest first; messages still awaiting a server timestamp sink to the end.
      images.sort((a, b) {
        final at = a.createdAt ?? a.clientCreatedAt;
        final bt = b.createdAt ?? b.clientCreatedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      return images;
    });
  }

  /// Ensures the chat document exists with up-to-date metadata.
  /// 
  /// This method:
  /// - Creates the chat document if it doesn't exist
  /// - Adds both admin UIDs and the user as participants
  /// - Updates last message info for the admin chat list
  /// - Increments unread count for admins when user sends a message
  /// - Increments unread count for user when admin sends a message
  /// - Updates hasUnreadFor array for efficient unread count queries
  /// - Uses merge: true to avoid overwriting existing fields
  /// - Uses a separate update() call for dot-notation nested fields
  ///   (adminUnreadCount.<uid>) because set()+merge does NOT reliably
  ///   interpret dot-separated keys as nested field paths in the Flutter SDK.
  Future<void> _ensureChatDoc(
      String chatId, {
        String? lastMessage,
        String? lastImageUrl,
        Timestamp? lastAt,
        bool incrementUnreadForAdmins = false,
        bool incrementUnreadForUser = false,
      }) async {
    final participants = <String>{chatId, ...adminIds}.toList();
    
    // Everything lands in one write. set(merge: true) merges nested maps field
    // by field, so 'adminUnreadCount' can be written as a nested map instead of
    // the dot-notation keys that would force a second update() round trip.
    // Both unread flags feed a single arrayUnion, so raising them together can
    // no longer drop one side from hasUnreadFor.
    final unreadFor = <String>[
      if (incrementUnreadForAdmins) ...adminIds,
      if (incrementUnreadForUser) chatId,
    ];

    final data = <String, dynamic>{
      'participants': participants,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastImageUrl != null) 'lastImageUrl': lastImageUrl,
      if (lastAt != null) 'lastMessageAt': lastAt,
      'updatedAt': FieldValue.serverTimestamp(),
      if (incrementUnreadForAdmins)
        'adminUnreadCount': {
          for (final adminUid in adminIds) adminUid: FieldValue.increment(1),
        },
      if (incrementUnreadForUser) 'userUnreadCount': FieldValue.increment(1),
      if (unreadFor.isNotEmpty) 'hasUnreadFor': FieldValue.arrayUnion(unreadFor),
    };

    await _chatDoc(chatId).set(data, SetOptions(merge: true));
  }

  /// Mark a chat as read for the current admin user.
  /// Resets the unread count to 0, updates lastReadAt timestamp,
  /// and removes admin from hasUnreadFor array for efficient count queries.
  /// 
  /// Uses update() because dot-notation keys (adminUnreadCount.<uid>) only
  /// resolve as nested field paths with update(), not with set()+merge.
  /// 
  /// Call this when admin opens a chat.
  Future<void> markChatAsRead(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null || !isAdminUid(currentUid)) {
      return;
    }
    
    try {
      await _chatDoc(chatId).update({
        'adminUnreadCount.$currentUid': 0,
        'adminLastReadAt.$currentUid': FieldValue.serverTimestamp(),
        'hasUnreadFor': FieldValue.arrayRemove([currentUid]),
      });
    } catch (e) {
      // Document may not exist yet (e.g. admin opens a new chat before any messages)
    }
  }

  /// Mark a chat as read for the current regular user.
  /// Resets the userUnreadCount to 0 and removes user from hasUnreadFor array.
  /// 
  /// Call this when a regular user opens their chat.
  Future<void> markChatAsReadForUser(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      return;
    }
    
    // Skip if current user is an admin (they use markChatAsRead instead)
    if (isAdminUid(currentUid)) {
      return;
    }
    
    // Only mark as read if this is the user's own chat
    if (currentUid != chatId) {
      return;
    }
    
    await _chatDoc(chatId).set({
      'userUnreadCount': 0,
      'userLastReadAt': FieldValue.serverTimestamp(),
      // Remove this user from hasUnreadFor for efficient count queries
      'hasUnreadFor': FieldValue.arrayRemove([currentUid]),
    }, SetOptions(merge: true));
  }

  /// Stream of unread message count for the current regular user.
  /// Returns the number of unread messages in their chat.
  /// 
  /// For regular users, they have only one chat (their own), so this
  /// returns the count of unread messages in that chat.
  Stream<int> userUnreadCountStream() {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      return Stream.value(0);
    }
    
    // If user is admin, return 0 (admins use totalUnreadChatsStream instead)
    if (isAdminUid(currentUid)) {
      return Stream.value(0);
    }
    
    // User's chat ID is their own UID
    return _chatDoc(currentUid)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) {
            return 0;
          }
          final data = snapshot.data() ?? {};
          final count = (data['userUnreadCount'] ?? 0) as int;
          return count;
        })
        .handleError((error, stackTrace) {
          return 0;
        });
  }

  /// Stream of total unread chat count for the current admin.
  /// Returns the number of chats that have unread messages.
  /// 
  /// OPTIMIZED: Uses 'hasUnreadFor' array field with arrayContains query.
  /// This only fetches chats with unread messages (not ALL chats),
  /// and Firestore's arrayContains is highly efficient with proper indexing.
  Stream<int> totalUnreadChatsStream() {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null || !isAdminUid(currentUid)) {
      return Stream.value(0);
    }
    
    // Efficient query: only get chats where this admin has unread messages
    // Instead of fetching ALL chats and filtering client-side
    return db
        .collection('chats')
        .where('hasUnreadFor', arrayContains: currentUid)
        .snapshots()
        .map((snapshot) {
          final count = snapshot.docs.length;
          return count;
        })
        .handleError((error, stackTrace) {
          return 0;
        });
  }

  /// Get unread count for a specific chat and admin from chat data.
  /// Helper method used by UI widgets.
  /// 
  /// Handles Firestore type variations safely:
  /// - Map can be Map<String, dynamic> or Map<Object?, Object?>
  /// - Values can be int or num (Firestore uses num for numbers)
  static int getUnreadCountFromChatData(Map<String, dynamic> chatData, String adminUid) {
    final unreadMapRaw = chatData['adminUnreadCount'];
    if (unreadMapRaw == null || unreadMapRaw is! Map) {
      return 0;
    }
    
    final value = unreadMapRaw[adminUid];
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  /// Send a text message to a specific chat.
  /// 
  /// Flow:
  /// 1. Validates input (non-empty, not already sending)
  /// 2. Ensures chat document exists with updated metadata
  /// 3. Adds message to messages subcollection
  /// 4. Clears the message controller
  /// 
  /// @param chatId The target chat ID (user UID in our model)
  Future<void> sendTextTo(String chatId) async {
    final text = messageController.text.trim();
    
    // Guard: Prevent empty messages or concurrent sends
    if (text.isEmpty || _sending) {
      return;
    }

    _sending = true;
    notifyListeners();
    
    try {
      // Determine who should get unread notification
      final isUserMessage = !isAdminUid(userId);
      final isAdminMessage = isAdminUid(userId);
      
      // Update chat document with latest message info
      // Clear lastImageUrl since this is a text-only message
      await _ensureChatDoc(
        chatId, 
        lastMessage: text, 
        lastImageUrl: '', 
        lastAt: Timestamp.now(),
        incrementUnreadForAdmins: isUserMessage,  // User sends → notify admins
        incrementUnreadForUser: isAdminMessage,   // Admin sends → notify user
      );
      
      // Add message to subcollection
      await _chatDoc(chatId).collection('messages').add({
        'chatId': chatId,
        'senderId': userId,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      });
      
      messageController.clear();
      
    } catch (e) {
      rethrow;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Send an image message to a specific chat.
  /// 
  /// Flow:
  /// 1. Validates no concurrent send/upload operations
  /// 2. Compresses the image to meet size requirements (≤5MB)
  /// 3. Uploads to Firebase Storage with progress tracking
  /// 4. Updates chat document with image metadata
  /// 5. Adds message to messages subcollection
  /// 6. Cleans up temporary files
  /// 
  /// Progress tracking:
  /// - During compression: uploadProgress is null (indeterminate)
  /// - During upload: uploadProgress is 0.0-1.0
  /// - UI can listen to isUploading, uploadProgress, and uploadKind
  /// 
  /// @param chatId The target chat ID (user UID in our model)
  /// @param image The image file selected by the user
  Future<void> sendImageTo(String chatId, XFile image) async {
    // Guard: Prevent concurrent operations
    if (_sending || isUploading) {
      return;
    }
    
    // Set upload state for UI feedback
    _uploadKind = UploadKind.chatImage;
    _uploadProgress = null; // null = indeterminate (compression phase)
    notifyListeners();

    File? tempCompressed;
    StreamSubscription<TaskSnapshot>? sub;
    
    try {
      // Step 1: Read original file
      final original = File(image.path);

      // Step 2: Compress image
      tempCompressed = await _compressImage(original);
      final uploadFile = tempCompressed.existsSync() ? tempCompressed : original;

      // Step 3: Prepare storage reference
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_rand(5)}.jpg';
      final path = 'chats/$chatId/$fileName';
      final ref = storage.ref(path);
      final meta = SettableMetadata(contentType: 'image/jpeg');

      // Step 4: Upload with progress tracking
      final task = ref.putFile(uploadFile, meta);
      _activeTask = task;
      
      sub = task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          notifyListeners();
        }
      });

      await task.whenComplete(() {});
      final url = await ref.getDownloadURL();

      // Step 5: Update chat document with image metadata
      // Determine who should get unread notification
      final isUserMessage = !isAdminUid(userId);
      final isAdminMessage = isAdminUid(userId);
      
      await _ensureChatDoc(
        chatId, 
        lastMessage: 'Fotoğraf', 
        lastImageUrl: url, 
        lastAt: Timestamp.now(),
        incrementUnreadForAdmins: isUserMessage,  // User sends → notify admins
        incrementUnreadForUser: isAdminMessage,   // Admin sends → notify user
      );

      // Step 6: Add message to subcollection
      await _chatDoc(chatId).collection('messages').add({
        'chatId': chatId,
        'senderId': userId,
        'imageUrl': url,
        'storagePath': path,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      });
    } catch (e) {
      rethrow;
    } finally {
      // Cleanup: Cancel subscription and delete temp files
      await sub?.cancel();
      
      try {
        if (tempCompressed != null && tempCompressed.existsSync()) {
          tempCompressed.deleteSync();
        }
      } catch (e) {
      }
      
      // Reset upload state
      _activeTask = null;
      _uploadProgress = null;
      _uploadKind = null;
      notifyListeners();
    }
  }


  // ===== Reactions =====

  /// Add (or replace) the current user's reaction on a message.
  ///
  /// Reactions are stored as a map on the message document keyed by the
  /// reactor's UID: `reactions.<uid> = emoji`. Only one reaction per user is
  /// kept, so calling this again with a different emoji overwrites the previous
  /// one (WhatsApp-style).
  ///
  /// Uses update() with a dot-notation field path so only the single nested
  /// key is written (the rest of the message document is untouched). update()
  /// — unlike set()+merge — reliably resolves `reactions.<uid>` as a nested
  /// field path, and creates the `reactions` map if it does not exist yet.
  ///
  /// @param chatId    The chat that owns the message (user UID in our model).
  /// @param messageId The message document id to react to.
  /// @param emoji     The reaction emoji (e.g. '👍' or '❤️').
  Future<void> setReaction(String chatId, String messageId, String emoji) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      await _chatDoc(chatId).collection('messages').doc(messageId).update({
        'reactions.$uid': emoji,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Remove the current user's reaction from a message (if any).
  ///
  /// Deletes the `reactions.<uid>` nested key via update()+FieldValue.delete().
  /// Safe to call even when the user has no reaction on the message.
  ///
  /// @param chatId    The chat that owns the message (user UID in our model).
  /// @param messageId The message document id to clear the reaction from.
  Future<void> removeReaction(String chatId, String messageId) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      await _chatDoc(chatId).collection('messages').doc(messageId).update({
        'reactions.$uid': FieldValue.delete(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Toggle the current user's reaction on a message.
  ///
  /// If the user's existing reaction already equals [emoji], it is removed
  /// (tapping the same reaction again clears it). Otherwise the reaction is set
  /// to [emoji]. [currentEmoji] is the reactor's existing reaction as known by
  /// the caller (from the streamed message), avoiding an extra read.
  Future<void> toggleReaction(
    String chatId,
    String messageId,
    String emoji, {
    String? currentEmoji,
  }) async {
    if (currentEmoji == emoji) {
      await removeReaction(chatId, messageId);
    } else {
      await setReaction(chatId, messageId, emoji);
    }
  }

  /// Cancel the current upload operation.
  ///
  /// This method attempts to cancel the active Firebase Storage upload task.
  /// Safe to call even if no upload is in progress.
  Future<void> cancelUpload() async {
    try {
      await _activeTask?.cancel();
    } catch (e) {
    }
  }

  /// Permanently delete an entire chat and all of its data.
  ///
  /// This is an ADMIN-ONLY destructive operation that:
  /// 1. Deletes every image referenced by the chat's messages from Firebase
  ///    Storage. This covers both direct chat uploads (chats/{chatId}/...) and
  ///    meal photos that were posted to the chat. Storage deletion is
  ///    best-effort per file: a single failure (e.g. the file was already
  ///    removed) is ignored and does not abort the rest of the operation.
  /// 2. Deletes all message documents in the messages subcollection
  ///    (in batches, since a document delete does not cascade to subcollections).
  /// 3. Deletes the chat document itself.
  ///
  /// NOTE: Meal photos are shared with the user's meal-tracking history, so
  /// deleting them here also removes those images from the meal records.
  ///
  /// Throws [StateError] if the caller is not an admin.
  ///
  /// @param chatId The chat to delete (user UID in our one-chat-per-user model)
  Future<void> deleteChat(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null || !isAdminUid(currentUid)) {
      throw StateError('Bu işlem için yetkiniz yok.');
    }

    final messagesRef = _chatDoc(chatId).collection('messages');

    // Step 1: Fetch all message documents
    final snapshot = await messagesRef.get();

    // Step 2: Delete referenced images from Storage (best-effort, de-duplicated).
    // refFromURL works for both direct chat uploads and meal photos since both
    // store full download URLs in the message's imageUrl field.
    final imageUrls = <String>{};
    for (final doc in snapshot.docs) {
      final url = (doc.data()['imageUrl'] as String?)?.trim() ?? '';
      if (url.isNotEmpty) imageUrls.add(url);
    }

    // Deleted in parallel batches: one round trip per image, serialised, made
    // clearing a busy chat take minutes.
    const storageDeleteConcurrency = 16;
    final urlList = imageUrls.toList();
    for (int i = 0; i < urlList.length; i += storageDeleteConcurrency) {
      final chunk = urlList.skip(i).take(storageDeleteConcurrency);
      await Future.wait(chunk.map((url) async {
        try {
          await storage.refFromURL(url).delete();
        } catch (e) {
        }
      }));
    }

    // Step 3: Delete message documents in batches (Firestore limit: 500 ops/batch)
    const batchLimit = 450;
    var batch = db.batch();
    var opCount = 0;
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= batchLimit) {
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      await batch.commit();
    }

    // Step 4: Delete the chat document itself
    await _chatDoc(chatId).delete();

    notifyListeners();
  }

  /// Compress an image to meet the maximum size requirement (5MB).
  /// 
  /// Strategy:
  /// - Uses multiple compression attempts with decreasing quality/dimensions
  /// - On Android/iOS: Uses flutter_image_compress (hardware-accelerated)
  /// - On Web/Desktop: Uses package:image (pure Dart fallback)
  /// 
  /// Compression attempts (in order):
  /// 1. 1600x1600, quality 85%
  /// 2. 1280x1280, quality 75%
  /// 3. 1024x1024, quality 65%
  /// 
  /// @param input The original image file
  /// @return The compressed image file (or original if compression failed)
  Future<File> _compressImage(File input) async {
    // Define compression attempts with decreasing quality/size
    final attempts = <({int w, int h, int q})>[
      (w: 1600, h: 1600, q: 85),  // First attempt: high quality
      (w: 1280, h: 1280, q: 75),  // Second attempt: medium quality
      (w: 1024, h: 1024, q: 65),  // Third attempt: lower quality
    ];

    File current = input;

    for (final a in attempts) {
      final outPath = _deriveOutPath(current.path);

      final result = await fic.FlutterImageCompress.compressAndGetFile(
        current.path,
        outPath,
        quality: a.q,
        minWidth: a.w,
        minHeight: a.h,
        format: fic.CompressFormat.jpeg,
        keepExif: false,
      );
      
      if (result == null) {
        continue;
      }
      
      final f = File(result.path);
      final size = await _safeFileLength(f);
      
      if (size <= MAX_IMG_SIZE) {
        return f;
      }
      
      current = f;
    }

    return current;
  }

  /// Safely get file length, returning -1 if the operation fails.
  Future<int> _safeFileLength(File f) async {
    try {
      return await f.length();
    } catch (e) {
      return -1;
    }
  }

  /// Generate a temporary output path for compressed images.
  /// Appends '_cmp.jpg' before the file extension.
  String _deriveOutPath(String inPath) {
    final idx = inPath.lastIndexOf('.');
    final base = idx > 0 ? inPath.substring(0, idx) : inPath;
    return '${base}_cmp.jpg';
  }

  /// Generate a random alphanumeric string of length n.
  /// Used for creating unique file names.
  String _rand(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
