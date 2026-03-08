// lib/providers/chat_manager_new.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:image/image.dart' as img;

import 'package:ngy_app/models/logger.dart';

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
class MessageData {
  final String id;
  final String chatId; //chatId if provided (admin viewing another user), otherwise current user's UID
  final String senderId;
  final String? text;
  final String? imageUrl;
  final String? storagePath;
  final Timestamp? createdAt;
  final Timestamp? clientCreatedAt;

  MessageData({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.storagePath,
    this.createdAt,
    this.clientCreatedAt,
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
    );
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
  final Logger logger = Logger.forClass(ChatManager);
  
  /// Maximum allowed image size: 5MB
  final MAX_IMG_SIZE = 5 * 1024 * 1024;
  
  /// Admin user IDs - these users have elevated permissions and are participants in all chats
  static const Set<String> adminIds = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  };

  /// Check if a given UID belongs to an admin user
  static bool isAdminUid(String uid) => adminIds.contains(uid);

  /// Get admin IDs set (for external access)
  static Set<String> get adminUids => adminIds;

  ChatManager({
    required this.db,
    required this.auth,
    required this.storage,
  }) {
    logger.info('ChatManager created. currentUser={}', [auth.currentUser?.uid]);
  }

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
    logger.debug('chatIdForUser: uid={}', [uid]);
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
    logger.debug('Subscribing to messages stream. chatId={}', [chatId]);
    return _messagesQuery(chatId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MessageData.fromSnapshot(d)).toList());
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
    logger.debug(
      'Ensuring chat doc. chatId={} participants={} lastMsg="{}" lastImageUrl={} incrementUnreadAdmins={} incrementUnreadUser={}', 
      [chatId, participants, lastMessage ?? 'none', lastImageUrl ?? 'none', incrementUnreadForAdmins, incrementUnreadForUser]
    );
    
    // Step 1: set() with merge for base fields (no dot-notation keys)
    final baseData = <String, dynamic>{
      'participants': participants,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastImageUrl != null) 'lastImageUrl': lastImageUrl,
      if (lastAt != null) 'lastMessageAt': lastAt,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    
    await _chatDoc(chatId).set(baseData, SetOptions(merge: true));
    
    // Step 2: update() for unread counters — update() properly resolves
    // dot-notation keys (e.g. 'adminUnreadCount.<uid>') as nested field paths.
    final needsUnreadUpdate = incrementUnreadForAdmins || incrementUnreadForUser;
    if (needsUnreadUpdate) {
      final unreadData = <String, dynamic>{};
      
      if (incrementUnreadForAdmins) {
        for (final adminUid in adminIds) {
          unreadData['adminUnreadCount.$adminUid'] = FieldValue.increment(1);
        }
        unreadData['hasUnreadFor'] = FieldValue.arrayUnion(adminIds.toList());
        logger.debug('Incrementing unread count for admins and updating hasUnreadFor');
      }
      
      if (incrementUnreadForUser) {
        unreadData['userUnreadCount'] = FieldValue.increment(1);
        unreadData['hasUnreadFor'] = FieldValue.arrayUnion([chatId]);
        logger.debug('Incrementing unread count for user and updating hasUnreadFor');
      }
      
      await _chatDoc(chatId).update(unreadData);
    }
    
    logger.debug('Chat doc ensured. chatId={}', [chatId]);
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
      logger.debug('markChatAsRead skipped: not logged in or not admin');
      return;
    }
    
    logger.info('Marking chat as read (admin). chatId={} adminUid={}', [chatId, currentUid]);
    
    try {
      await _chatDoc(chatId).update({
        'adminUnreadCount.$currentUid': 0,
        'adminLastReadAt.$currentUid': FieldValue.serverTimestamp(),
        'hasUnreadFor': FieldValue.arrayRemove([currentUid]),
      });
    } catch (e) {
      // Document may not exist yet (e.g. admin opens a new chat before any messages)
      logger.warn('markChatAsRead: update failed (doc may not exist). chatId={} error={}', [chatId, e]);
    }
    
    logger.debug('Chat marked as read (admin). chatId={}', [chatId]);
  }

  /// Mark a chat as read for the current regular user.
  /// Resets the userUnreadCount to 0 and removes user from hasUnreadFor array.
  /// 
  /// Call this when a regular user opens their chat.
  Future<void> markChatAsReadForUser(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      logger.debug('markChatAsReadForUser skipped: not logged in');
      return;
    }
    
    // Skip if current user is an admin (they use markChatAsRead instead)
    if (isAdminUid(currentUid)) {
      logger.debug('markChatAsReadForUser skipped: user is admin');
      return;
    }
    
    // Only mark as read if this is the user's own chat
    if (currentUid != chatId) {
      logger.debug('markChatAsReadForUser skipped: chatId does not match current user');
      return;
    }
    
    logger.info('Marking chat as read (user). chatId={} userId={}', [chatId, currentUid]);
    
    await _chatDoc(chatId).set({
      'userUnreadCount': 0,
      'userLastReadAt': FieldValue.serverTimestamp(),
      // Remove this user from hasUnreadFor for efficient count queries
      'hasUnreadFor': FieldValue.arrayRemove([currentUid]),
    }, SetOptions(merge: true));
    
    logger.debug('Chat marked as read (user). chatId={}', [chatId]);
  }

  /// Stream of unread message count for the current regular user.
  /// Returns the number of unread messages in their chat.
  /// 
  /// For regular users, they have only one chat (their own), so this
  /// returns the count of unread messages in that chat.
  Stream<int> userUnreadCountStream() {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      logger.debug('userUnreadCountStream: returning 0 (not logged in)');
      return Stream.value(0);
    }
    
    // If user is admin, return 0 (admins use totalUnreadChatsStream instead)
    if (isAdminUid(currentUid)) {
      logger.debug('userUnreadCountStream: returning 0 (user is admin)');
      return Stream.value(0);
    }
    
    logger.info('userUnreadCountStream: starting stream for user {}', [currentUid]);
    
    // User's chat ID is their own UID
    return _chatDoc(currentUid)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) {
            logger.debug('userUnreadCountStream: chat does not exist yet');
            return 0;
          }
          final data = snapshot.data() ?? {};
          final count = (data['userUnreadCount'] ?? 0) as int;
          logger.debug('User unread count: {}', [count]);
          return count;
        })
        .handleError((error, stackTrace) {
          logger.err('userUnreadCountStream error: {}', [error]);
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
      logger.debug('totalUnreadChatsStream: returning 0 (not admin or not logged in)');
      return Stream.value(0);
    }
    
    logger.info('totalUnreadChatsStream: starting stream for admin {}', [currentUid]);
    
    // Efficient query: only get chats where this admin has unread messages
    // Instead of fetching ALL chats and filtering client-side
    return db
        .collection('chats')
        .where('hasUnreadFor', arrayContains: currentUid)
        .snapshots()
        .map((snapshot) {
          final count = snapshot.docs.length;
          logger.info('Total unread chats count: {} (efficient query)', [count]);
          return count;
        })
        .handleError((error, stackTrace) {
          logger.err('totalUnreadChatsStream error: {}', [error]);
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
    
    final value = (unreadMapRaw as Map)[adminUid];
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
      logger.debug(
        'sendTextTo skipped. chatId={} isEmpty={} alreadySending={}', 
        [chatId, text.isEmpty, _sending]
      );
      return;
    }

    _sending = true;
    notifyListeners();
    
    try {
      logger.info('Sending text message. chatId={} senderId={} length={}', [chatId, userId, text.length]);
      
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
      final ref = await _chatDoc(chatId).collection('messages').add({
        'chatId': chatId,
        'senderId': userId,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      });
      
      logger.info('Text message sent successfully. messageId={} chatId={}', [ref.id, chatId]);
      messageController.clear();
      
    } catch (e, st) {
      logger.err('sendTextTo failed. chatId={} error={}', [chatId, e]);
      if (kDebugMode) logger.debug('Stack trace:\n{}', [st]);
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
      logger.debug(
        'sendImageTo skipped due to concurrent operation. chatId={} sending={} isUploading={}', 
        [chatId, sending, isUploading]
      );
      return;
    }
    
    // Set upload state for UI feedback
    _uploadKind = UploadKind.chatImage;
    _uploadProgress = null; // null = indeterminate (compression phase)
    notifyListeners();

    File? tempCompressed;
    StreamSubscription<TaskSnapshot>? sub;
    
    try {
      logger.info('Starting image send. chatId={} senderId={} srcPath={}', [chatId, userId, image.path]);

      // Step 1: Read original file
      final original = File(image.path);
      final originalSize = await _safeFileLength(original);
      logger.debug('Original image size: {} bytes ({:.2f} MB)', [originalSize, originalSize / (1024 * 1024)]);

      // Step 2: Compress image
      logger.debug('Starting image compression...');
      tempCompressed = await _compressImage(original);
      final uploadFile = tempCompressed.existsSync() ? tempCompressed : original;
      final uploadSize = await _safeFileLength(uploadFile);
      logger.debug('Compression complete. finalSize={} bytes ({:.2f} MB)', [uploadSize, uploadSize / (1024 * 1024)]);

      // Step 3: Prepare storage reference
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_rand(5)}.jpg';
      final path = 'chats/$chatId/$fileName';
      final ref = storage.ref(path);
      final meta = SettableMetadata(contentType: 'image/jpeg');
      logger.debug('Storage path: {}', [path]);

      // Step 4: Upload with progress tracking
      int lastLogged = -1;
      final task = ref.putFile(uploadFile, meta);
      _activeTask = task;
      
      sub = task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          final pct = ((snapshot.bytesTransferred / snapshot.totalBytes) * 100).floor();
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          
          // Log at 0%, 25%, 50%, 75%, 100% to avoid spam
          if (pct == 100 || pct >= lastLogged + 25 || pct == 0) {
            lastLogged = pct;
            logger.debug('Upload progress: {}% ({}/{} bytes)', [pct, snapshot.bytesTransferred, snapshot.totalBytes]);
          }
          notifyListeners();
        }
      });

      await task.whenComplete(() {});
      final url = await ref.getDownloadURL();
      logger.debug('Upload complete. downloadUrl={}', [url]);

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
      final refMsg = await _chatDoc(chatId).collection('messages').add({
        'chatId': chatId,
        'senderId': userId,
        'imageUrl': url,
        'storagePath': path,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      });
      
      logger.info('Image message sent successfully. messageId={} chatId={} storagePath={}', [refMsg.id, chatId, path]);
      
    } catch (e, st) {
      logger.err('sendImageTo failed. chatId={} error={}', [chatId, e]);
      if (kDebugMode) logger.debug('Stack trace:\n{}', [st]);
      rethrow;
    } finally {
      // Cleanup: Cancel subscription and delete temp files
      await sub?.cancel();
      
      try {
        if (tempCompressed != null && tempCompressed.existsSync()) {
          tempCompressed.deleteSync();
          logger.debug('Temporary compressed file deleted: {}', [tempCompressed.path]);
        }
      } catch (e) {
        logger.warn('Failed to delete temporary compressed file: {}', [e]);
      }
      
      // Reset upload state
      _activeTask = null;
      _uploadProgress = null;
      _uploadKind = null;
      notifyListeners();
      
      logger.info('Image send operation finished. chatId={}', [chatId]);
    }
  }


  /// Cancel the current upload operation.
  /// 
  /// This method attempts to cancel the active Firebase Storage upload task.
  /// Safe to call even if no upload is in progress.
  Future<void> cancelUpload() async {
    try {
      logger.info('Upload cancellation requested. activeTask={}', [_activeTask != null]);
      await _activeTask?.cancel();
      logger.info('Upload cancelled successfully');
    } catch (e) {
      logger.warn('Upload cancellation failed: {}', [e]);
    }
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

    // Use flutter_image_compress only on Android/iOS (hardware-accelerated)
    final canUseFIC = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    logger.debug('Compression method: {}', [canUseFIC ? 'FlutterImageCompress' : 'package:image']);

    File current = input;

    for (final a in attempts) {
      final outPath = _deriveOutPath(current.path);

      if (canUseFIC) {
        // Use flutter_image_compress for Android/iOS
        logger.debug('[FIC] Compression attempt -> dimensions:{}x{} quality:{}%', [a.w, a.h, a.q]);
        
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
          logger.warn('[FIC] Compression returned null. outPath={}', [outPath]);
          continue;
        }
        
        final f = File(result.path);
        final size = await _safeFileLength(f);
        logger.debug('[FIC] Result size: {} bytes ({:.2f} MB)', [size, size / (1024 * 1024)]);
        
        if (size <= MAX_IMG_SIZE) {
          logger.info('[FIC] Compression successful. finalSize={} bytes', [size]);
          return f;
        }
        
        current = f;
        
      } else {
        // Fallback: pure Dart compression using package:image (Web/Desktop)
        logger.debug('[IMG] Compression attempt -> box:{}x{} quality:{}%', [a.w, a.h, a.q]);
        
        final bytes = await current.readAsBytes();
        final decoded = img.decodeImage(bytes);
        
        if (decoded == null) {
          logger.warn('[IMG] Failed to decode image. path={}', [current.path]);
          continue;
        }

        // Resize to fit within box while preserving aspect ratio
        final resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? a.w : null,
          height: decoded.height >= decoded.width ? a.h : null,
          interpolation: img.Interpolation.average,
        );

        final jpg = img.encodeJpg(resized, quality: a.q);
        final f = File(outPath)..writeAsBytesSync(jpg, flush: true);
        final size = await _safeFileLength(f);
        logger.debug('[IMG] Result size: {} bytes ({:.2f} MB)', [size, size / (1024 * 1024)]);
        
        if (size <= MAX_IMG_SIZE) {
          logger.info('[IMG] Compression successful. finalSize={} bytes', [size]);
          return f;
        }
        
        current = f;
      }
    }

    logger.warn('Compression did not reach target size after all attempts. Using last result or original.');
    return current;
  }

  /// Safely get file length, returning -1 if the operation fails.
  Future<int> _safeFileLength(File f) async {
    try {
      return await f.length();
    } catch (e) {
      logger.warn('Failed to get file length: {}', [e]);
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
    logger.info('ChatManager disposed.');
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
