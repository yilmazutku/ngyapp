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
/// - Both admin UIDs are automatically added as participants in every chat
/// - Supports admin viewing any user's chat
/// 
/// Admin UIDs:
/// - Nilay: 0MvvbZsjbmNPW4QYShRNSOOtkE43
/// - Utku: 9CwKr0S4mDdZB4Wlc8BK4W8qsT42
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
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  /// Check if a given UID belongs to an admin user
  static bool isAdminUid(String uid) => adminIds.contains(uid);

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
  /// - Uses merge: true to avoid overwriting existing fields
  Future<void> _ensureChatDoc(
      String chatId, {
        String? lastMessage,
        String? lastImageUrl,
        Timestamp? lastAt,
      }) async {
    final participants = <String>{chatId, ...adminIds}.toList();
    logger.debug(
      'Ensuring chat doc. chatId={} participants={} lastMsg="{}" lastImageUrl={}', 
      [chatId, participants, lastMessage ?? 'none', lastImageUrl ?? 'none']
    );
    
    await _chatDoc(chatId).set({
      'participants': participants,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastImageUrl != null) 'lastImageUrl': lastImageUrl,
      if (lastAt != null) 'lastMessageAt': lastAt,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    logger.debug('Chat doc ensured. chatId={}', [chatId]);
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
      
      // Update chat document with latest message info
      // Clear lastImageUrl since this is a text-only message
      await _ensureChatDoc(chatId, lastMessage: text, lastImageUrl: '', lastAt: Timestamp.now());
      
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
      await _ensureChatDoc(
        chatId, 
        lastMessage: 'Fotoğraf', 
        lastImageUrl: url, 
        lastAt: Timestamp.now()
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
