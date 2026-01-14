// lib/pages/chat_page_new.dart
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/logger.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/widgets/chat_image_preview.dart';
import 'package:ngy_app/utils/dialog_utils.dart';
import 'package:ngy_app/services/fcm_service.dart';

import '../constants/app_constants.dart';

/// ChatPage displays the chat interface for both regular users and admins.
/// 
/// Features:
/// - Send text messages
/// - Send images from gallery or camera
/// - Upload meal photos
/// - View message history with timestamps
/// - Real-time updates via Firestore streams
/// 
/// Admin behavior:
/// - Admins can view any user's chat by passing overrideChatId
/// - All features are available
/// 
/// User behavior:
/// - Regular users always view their own chat (overrideChatId is null)
/// - All features including meal upload are available
class ChatPage extends StatefulWidget {
  /// Optional chat ID override for admin users.
  /// - If null: Opens the current user's own chat
  /// - If non-null: Opens the specified user's chat (admin only)
  final String? overrideChatId;
  
  const ChatPage({super.key, this.overrideChatId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final Logger logger = Logger.forClass(_ChatPageState);
  final ImagePicker _picker = ImagePicker();
  static const _months = [
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  /// Current authenticated user's UID
  late final String _currentUid;
  
  /// The resolved chat ID (cached to avoid recalculation)
  late final String _chatId;
  
  /// Whether the current user is an admin
  late final bool _isAdminUser;
  
  /// Whether meal upload should be enabled for this chat view
  late final bool _canUploadMeals;
  
  /// Cached messages stream to prevent recreation on rebuilds
  Stream<List<MessageData>>? _messagesStream;

  @override
  void initState() {
    super.initState();
    
    // Register for app lifecycle changes to handle background/foreground transitions
    WidgetsBinding.instance.addObserver(this);
    
    _currentUid = FirebaseAuth.instance.currentUser!.uid;
    
    // Resolve chat ID once and cache it
    _chatId = widget.overrideChatId ?? _currentUid;
    
    // Determine if current user is an admin
    _isAdminUser = ChatManager.isAdminUid(_currentUid);
    
    // Meal upload is available for all users
    _canUploadMeals = true;
    
    // Set active chat ID to suppress notifications for this chat
    FcmService().setActiveChatId(_chatId);
    
    // Mark chat as read based on user type
    if (_isAdminUser) {
      _markChatAsReadForAdmin();
    } else {
      _markChatAsReadForUser();
    }
    
    logger.info(
      'ChatPage initialized. currentUid={} isAdmin={} chatId={} canUploadMeals={}',
      [_currentUid, _isAdminUser, _chatId, _canUploadMeals]
    );
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Clear active chat ID to resume receiving notifications
    FcmService().clearActiveChatId();
    logger.info('ChatPage disposed. currentUid={}', [_currentUid]);
    super.dispose();
  }

  /// Mark chat as read for admin user (resets unread count)
  Future<void> _markChatAsReadForAdmin() async {
    try {
      final chatManager = context.read<ChatManager>();
      await chatManager.markChatAsRead(_chatId);
      logger.debug('Chat marked as read for admin. chatId={}', [_chatId]);
    } catch (e) {
      logger.warn('Failed to mark chat as read (admin): {}', [e]);
    }
  }

  /// Mark chat as read for regular user (resets unread count)
  Future<void> _markChatAsReadForUser() async {
    try {
      final chatManager = context.read<ChatManager>();
      await chatManager.markChatAsReadForUser(_chatId);
      logger.debug('Chat marked as read for user. chatId={}', [_chatId]);
    } catch (e) {
      logger.warn('Failed to mark chat as read (user): {}', [e]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // When app goes to background, clear active chat ID so notifications can come through
    // When app returns to foreground, re-set active chat ID to suppress in-app banners
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App is going to background - allow notifications
      FcmService().clearActiveChatId();
      logger.info('App backgrounded, cleared active chat ID to allow notifications');
    } else if (state == AppLifecycleState.resumed) {
      // App is back in foreground - suppress notifications for this chat again
      FcmService().setActiveChatId(_chatId);
      // Re-mark as read when returning to foreground
      if (_isAdminUser) {
        _markChatAsReadForAdmin();
      } else {
        _markChatAsReadForUser();
      }
      logger.info('App resumed, re-set active chat ID to suppress in-app notifications');
    }
  }

  /// Check and request photo library permission.
  /// Returns true if permission is granted, false otherwise.
  /// Shows a dialog to open Settings if permission is permanently denied.
  Future<bool> _checkPhotoPermission() async {
    Permission permission;
    if (Platform.isIOS) {
      permission = Permission.photos;
    } else {
      permission = Permission.photos;
    }

    var status = await permission.status;
    logger.info('Photo permission initial status: {}', [status.toString()]);

    // Already granted or limited access - proceed
    if (status.isGranted || status.isLimited) {
      return true;
    }

    // On iOS, 'denied' means we can still request (user hasn't seen dialog yet)
    // On iOS, 'permanentlyDenied' means user denied and we must go to settings
    // Always try to request first if not permanently denied
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      logger.info('Requesting photo permission...');
      status = await permission.request();
      logger.info('Photo permission after request: {}', [status.toString()]);
      
      if (status.isGranted || status.isLimited) {
        return true;
      }
    }

    // Permission denied or permanently denied - show dialog to open Settings
    if (!mounted) return false;
    
    final shouldOpenSettings = await DialogUtils.openConfirm(
      context,
      title: 'Fotoğraf İzni Gerekli',
      message: 'Fotoğraf göndermek için galeri erişim izni gereklidir.\n\n'
          'Lütfen Ayarlar\'a giderek fotoğraf erişimine izin verin.',
      confirmText: 'Ayarlara Git',
      cancelText: 'İptal',
    );

    if (shouldOpenSettings) {
      await openAppSettings();
    }
    return false;
  }

  /// Check and request camera permission.
  /// Returns true if permission is granted, false otherwise.
  /// Shows a dialog to open Settings if permission is permanently denied.
  Future<bool> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    logger.info('Camera permission initial status: {}', [status.toString()]);

    // Already granted - proceed
    if (status.isGranted) {
      return true;
    }

    // On iOS, 'denied' means we can still request (user hasn't seen dialog yet)
    // On iOS, 'permanentlyDenied' means user denied and we must go to settings
    // Always try to request first if not permanently denied or restricted
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      logger.info('Requesting camera permission...');
      status = await Permission.camera.request();
      logger.info('Camera permission after request: {}', [status.toString()]);
      
      if (status.isGranted) {
        return true;
      }
    }

    // Permission denied or permanently denied - show dialog to open Settings
    if (!mounted) return false;
    
    final shouldOpenSettings = await DialogUtils.openConfirm(
      context,
      title: 'Kamera İzni Gerekli',
      message: 'Fotoğraf çekebilmek için kamera erişim izni gereklidir.\n\n'
          'Lütfen Ayarlar\'a giderek kamera erişimine izin verin.',
      confirmText: 'Ayarlara Git',
      cancelText: 'İptal',
    );

    if (shouldOpenSettings) {
      await openAppSettings();
    }
    return false;
  }

  /// Pick an image from the gallery and send it to the chat.
  /// 
  /// Flow:
  /// 1. Opens gallery picker
  /// 2. Shows loading dialog during upload
  /// 3. Sends image via ChatManager
  /// 4. Handles errors with user-friendly dialogs
  Future<void> _pickAndSendImage() async {
    // Check permission first
    final hasPermission = await _checkPhotoPermission();
    if (!hasPermission) {
      logger.info('Photo permission denied, aborting gallery pick');
      return;
    }

    final chat = context.read<ChatManager>();
    logger.info('Gallery image picker opened. chatId={}', [_chatId]);

    // Step 1: Pick image from gallery
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      logger.debug('Gallery image pick cancelled by user');
      return;
    }
    
    logger.debug('Gallery image selected. path={}', [image.path]);
    
    // Step 2: Show loading dialog (without await to avoid context issues)
    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Görsel yükleniyor...');
      loadingOpen = true;
      logger.debug('Loading dialog opened');
    }
    
    try {
      // Step 3: Send image
      logger.debug('Starting image send operation...');
      await chat.sendImageTo(_chatId, image);
      logger.info('Gallery image sent successfully. chatId={}', [_chatId]);
      
      // Close loading dialog on success
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        logger.debug('Loading dialog closed');
      }
      
    } catch (e, st) {
      logger.err('Gallery image send failed. chatId={} error={}', [_chatId, e]);
      if (kDebugMode) logger.debug('Stack trace:\n{}', [st]);
      
      // Close loading dialog before showing error
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        logger.debug('Loading dialog closed (error case)');
      }
      
      // Show error dialog
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Görsel gönderilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Capture an image from the camera and send it to the chat.
  /// 
  /// Flow:
  /// 1. Opens camera for capture
  /// 2. Shows loading dialog during upload
  /// 3. Sends image via ChatManager
  /// 4. Handles errors with user-friendly dialogs
  Future<void> _captureAndSendImage() async {
    // Check camera permission first
    final hasPermission = await _checkCameraPermission();
    if (!hasPermission) {
      logger.info('Camera permission denied, aborting capture');
      return;
    }

    final chat = context.read<ChatManager>();
    logger.info('Camera capture opened. chatId={}', [_chatId]);

    // Step 1: Capture image from camera
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) {
      logger.debug('Camera capture cancelled by user');
      return;
    }
    
    logger.debug('Camera image captured. path={}', [image.path]);
    
    // Step 2: Show loading dialog (without await to avoid context issues)
    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Görsel yükleniyor...');
      loadingOpen = true;
      logger.debug('Loading dialog opened');
    }
    
    try {
      // Step 3: Send image
      logger.debug('Starting image send operation...');
      await chat.sendImageTo(_chatId, image);
      logger.info('Camera image sent successfully. chatId={}', [_chatId]);
      
      // Close loading dialog on success
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        logger.debug('Loading dialog closed');
      }
      
    } catch (e, st) {
      logger.err('Camera image send failed. chatId={} error={}', [_chatId, e]);
      if (kDebugMode) logger.debug('Stack trace:\n{}', [st]);
      
      // Close loading dialog before showing error
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        logger.debug('Loading dialog closed (error case)');
      }
      
      // Show error dialog
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Kamera görüntüsü gönderilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Start the meal upload flow.
  /// 
  /// This is a multi-step process:
  /// 1. User selects meal type (breakfast, lunch, dinner, snack)
  /// 2. User selects image source (gallery or camera)
  /// 3. User picks/captures image
  /// 4. Image is uploaded to storage and posted to chat
  Future<void> _startMealUploadFlow() async {
    final chat = context.read<ChatManager>();
    
    // Guard: Meal upload only allowed for your own chat
    if (!_canUploadMeals) {
      logger.warn(
        'Meal upload blocked. currentUid={} overrideChatId={} canUpload={}',
        [_currentUid, widget.overrideChatId ?? 'null', _canUploadMeals]
      );
      return;
    }

    logger.info('Meal upload flow started. currentUid={}', [_currentUid]);
    
    // Step 1: Choose meal type
    final Meals? meal = await _chooseMeal();
    if (meal == null) {
      logger.debug('Meal upload cancelled: No meal selected');
      return;
    }
    logger.debug('Meal selected: {}', [meal.name]);

    // Step 2: Choose image source
    final ImageSource? src = await _chooseSource();
    if (src == null) {
      logger.debug('Meal upload cancelled: No source selected');
      return;
    }
    logger.debug('Image source selected: {}', [src.name]);

    // Step 2.5: Check permission based on selected source
    final hasPermission = src == ImageSource.camera 
        ? await _checkCameraPermission() 
        : await _checkPhotoPermission();
    if (!hasPermission) {
      logger.info('Permission denied for {}, aborting meal upload', [src.name]);
      return;
    }

    // Step 3: Pick/capture image
    final XFile? image = await _picker.pickImage(source: src);
    if (image == null) {
      logger.debug('Meal upload cancelled: No image selected');
      return;
    }
    logger.debug('Meal image selected. path={}', [image.path]);

    // Step 4: Upload with loading dialog
    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Öğün fotoğrafı yükleniyor...');
      loadingOpen = true;
      logger.debug('Loading dialog opened');
    }

    try {
      logger.info('Starting meal image upload. meal={} userId={}', [meal.name, _currentUid]);
      
      // Use the MealStateManager for meal uploads
      final mealStateManager = Provider.of<MealManager>(context, listen: false);
      final downloadUrl = await mealStateManager.uploadMealImg(
        meal: meal,
        image: image,
        userId: _currentUid,
        subscriptionId: _currentUid, // Use appropriate subscription ID if available
        alsoPostToChat: true, // Post to chat automatically
        chatManager: chat, // Pass the ChatManager instance
      );
      
      logger.debug('Meal upload completed. downloadUrl={}', [downloadUrl ?? 'null']);
      
      // Close loading dialog before showing success
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        logger.debug('Loading dialog closed');
      }
      
      if (downloadUrl != null) {
        logger.info('Meal upload successful. meal={} userId={}', [meal.name, _currentUid]);
        
        if (!mounted) return;
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Öğün fotoğrafı yüklendi.',
        );
      } else {
        throw Exception('Öğün fotoğrafı yüklenemedi (downloadUrl is null)');
      }
      
    } catch (e, st) {
      logger.err('Meal upload failed. meal={} userId={} error={}', [meal.name ?? 'unknown', _currentUid, e]);
      if (kDebugMode) logger.debug('Stack trace:\n{}', [st]);
      
      // Close loading dialog before showing error
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        logger.debug('Loading dialog closed (error case)');
      }
      
      // Show error dialog
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Öğün fotoğrafı yüklenemedi: ${e.toString()}',
      );
    }
  }

  /// Show a modal bottom sheet for meal type selection.
  /// 
  /// Returns the selected Meals enum value, or null if cancelled.
  Future<Meals?> _chooseMeal() async {
    logger.debug('Opening meal chooser bottom sheet');
    
    return showModalBottomSheet<Meals>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Öğün Seçin', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final m in Meals.values)
                ListTile(
                  title: Text(m.label),
                  subtitle: Text(m.defaultTime),
                  onTap: () {
                    logger.debug('Meal selected in bottom sheet: {} ({})', [m.name, m.label]);
                    Navigator.of(ctx).pop(m);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Show a dialog for image source selection (gallery or camera).
  /// 
  /// Returns the selected ImageSource, or null if cancelled.
  Future<ImageSource?> _chooseSource() async {
    logger.debug('Opening image source selection dialog');
    
    return showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kaynak'),
        content: const Text('Görsel kaynağını seçin.'),
        actions: [
          TextButton(
            onPressed: () {
              logger.debug('Image source selected: gallery');
              Navigator.pop(context, ImageSource.gallery);
            },
            child: const Text('Galeri'),
          ),
          TextButton(
            onPressed: () {
              logger.debug('Image source selected: camera');
              Navigator.pop(context, ImageSource.camera);
            },
            child: const Text('Kamera'),
          ),
        ],
      ),
    );
  }

  /// Get or create the cached messages stream
  Stream<List<MessageData>> _getMessagesStream(ChatManager chat) {
    _messagesStream ??= chat.messagesStreamFor(_chatId);
    return _messagesStream!;
  }

  @override
  Widget build(BuildContext context) {
    // Use read() instead of watch() - we'll use Selector for specific rebuilds
    final chat = context.read<ChatManager>();

    return Scaffold(
      appBar: AppBar(
        // If admin is viewing a user's chat, show user's name as title
        // Otherwise show the default chat title
        title: widget.overrideChatId != null && _isAdminUser
            ? _buildUserNameTitle(_chatId)
            : Text(PushNotificationReference.chatAdminToUserTitle),
      ),
      body: Column(
        children: [
          // Upload progress indicator - only rebuilds when upload state changes
          Selector<ChatManager, ({bool isUploading, double? progress})>(
            selector: (_, chat) => (isUploading: chat.isUploading, progress: chat.uploadProgress),
            builder: (context, state, _) {
              if (!state.isUploading) return const SizedBox.shrink();
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(value: state.progress),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        logger.info('Upload cancel button tapped');
                        context.read<ChatManager>().cancelUpload();
                      },
                      child: const Text('İptal'),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Messages list - uses cached stream, doesn't rebuild on ChatManager changes
          Expanded(
            child: StreamBuilder<List<MessageData>>(
              stream: _getMessagesStream(chat),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final items = snap.data ?? const <MessageData>[];
                
                if (items.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok.'));
                }
                
                return ListView.builder(
                  controller: chat.scrollController,
                  reverse: true, // Newest messages at bottom
                  itemCount: items.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    message: items[i],
                    isMe: items[i].senderId == _currentUid,
                    onImageTap: (url) => _showImageDialog(context, url),
                  ),
                );
              },
            ),
          ),

          // Input row - only rebuilds when sending/uploading state changes
          _ChatInputRow(
            chatId: _chatId,
            canUploadMeals: _canUploadMeals,
            onPickImage: _pickAndSendImage,
            onCaptureImage: _captureAndSendImage,
            onMealUpload: _startMealUploadFlow,
            logger: logger,
          ),
        ],
      ),
    );
  }

  /// Build a title widget displaying the user's full name.
  /// 
  /// Fetches user details from Firestore and displays name + surname.
  /// Shows loading text while fetching, and falls back to "Sohbet" on error.
  Widget _buildUserNameTitle(String userId) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    
    return FutureBuilder(
      future: userProvider.fetchUserDetails(userId: userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text('Yükleniyor...');
        }
        
        String displayName = 'Sohbet'; // Fallback
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          final firstName = user.name.trim();
          final lastName = user.surname.trim();
          displayName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
          logger.debug('User name loaded for chat title: {}', [displayName]);
        } else if (snapshot.hasError) {
          logger.warn('Failed to load user name for chat title: {}', [snapshot.error]);
        }
        
        return Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  /// Format a DateTime for display in chat messages.
  /// 
  /// Format rules:
  /// - Today: "HH:mm"
  /// - Yesterday: "Dün HH:mm"
  /// - This year: "DD Month HH:mm"
  /// - Other years: "DD Month YYYY HH:mm"
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dt.year, dt.month, dt.day);
    
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final time = '$h:$m';
    
    // Same day: just show time
    if (messageDate == today) {
      return time;
    }
    
    // Yesterday: show "Dün HH:mm"
    if (messageDate == yesterday) {
      return 'Dün $time';
    }
    
    // Older: show "DD Ay HH:mm"
    final day = dt.day;
    final month = _months[dt.month];
    
    // If older than this year, include year
    if (dt.year != now.year) {
      return '$day $month ${dt.year} $time';
    }
    
    return '$day $month $time';
  }

  /// Show a full-screen image dialog with zoom support.
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text('Görsel yüklenemedi', style: TextStyle(color: Colors.red)),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extracted message bubble widget - prevents parent rebuilds
class _MessageBubble extends StatelessWidget {
  final MessageData message;
  final bool isMe;
  final void Function(String url) onImageTap;

  static const _months = [
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.onImageTap,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dt.year, dt.month, dt.day);
    
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final time = '$h:$m';
    
    if (messageDate == today) return time;
    if (messageDate == yesterday) return 'Dün $time';
    
    final day = dt.day;
    final month = _months[dt.month];
    
    if (dt.year != now.year) {
      return '$day $month ${dt.year} $time';
    }
    
    return '$day $month $time';
  }

  @override
  Widget build(BuildContext context) {
    final ts = message.createdAt ?? message.clientCreatedAt;
    final timeStr = ts != null ? _formatTime(ts.toDate()) : 'Gönderiliyor…';
    final bubbleColor = isMe ? Colors.blue.shade100 : Colors.grey.shade300;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: align,
        children: [
          // Text message bubble
          if ((message.text ?? '').isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: align,
                children: [
                  Text(message.text!, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          
          // Image preview
          if (message.imageUrl != null)
            ChatImagePreview(
              imageUrl: message.imageUrl,
              onTap: () => onImageTap(message.imageUrl!),
              usePlaceholder: message.createdAt == null,
            ),
          
          // Timestamp below image
          if (message.imageUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

/// Extracted input row widget - uses Selector for targeted rebuilds
class _ChatInputRow extends StatefulWidget {
  final String chatId;
  final bool canUploadMeals;
  final VoidCallback onPickImage;
  final VoidCallback onCaptureImage;
  final VoidCallback onMealUpload;
  final Logger logger;

  const _ChatInputRow({
    required this.chatId,
    required this.canUploadMeals,
    required this.onPickImage,
    required this.onCaptureImage,
    required this.onMealUpload,
    required this.logger,
  });

  @override
  State<_ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<_ChatInputRow> with SingleTickerProviderStateMixin {
  bool _isMenuOpen = false;
  late final AnimationController _animationController;
  late final Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _closeMenuAndRun(VoidCallback action) {
    if (_isMenuOpen) {
      setState(() {
        _isMenuOpen = false;
        _animationController.reverse();
      });
    }
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        // Only rebuild when sending/uploading state changes
        child: Selector<ChatManager, ({bool sending, bool uploading})>(
          selector: (_, chat) => (sending: chat.sending, uploading: chat.isUploading),
          builder: (context, state, _) {
            final isDisabled = state.sending || state.uploading;
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Expandable attachment menu
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _isMenuOpen
                      ? Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _AttachmentOption(
                                icon: Icons.photo_library_rounded,
                                label: 'Galeri',
                                color: Colors.purple,
                                onTap: isDisabled ? null : () => _closeMenuAndRun(widget.onPickImage),
                              ),
                              _AttachmentOption(
                                icon: Icons.camera_alt_rounded,
                                label: 'Kamera',
                                color: Colors.blue,
                                onTap: isDisabled ? null : () => _closeMenuAndRun(widget.onCaptureImage),
                              ),
                              if (widget.canUploadMeals)
                                _AttachmentOption(
                                  icon: Icons.restaurant_rounded,
                                  label: 'Öğün Yükle',
                                  color: Colors.orange,
                                  onTap: isDisabled ? null : () => _closeMenuAndRun(widget.onMealUpload),
                                ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                
                // Input row
                Row(
                  children: [
                    // Plus button to toggle menu
                    RotationTransition(
                      turns: _rotationAnimation,
                      child: IconButton(
                        icon: Icon(
                          Icons.add_circle_rounded,
                          color: _isMenuOpen ? colorScheme.primary : null,
                          size: 28,
                        ),
                        onPressed: isDisabled ? null : _toggleMenu,
                        tooltip: 'Ekler',
                      ),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // Text input field
                    Expanded(
                      child: TextField(
                        controller: context.read<ChatManager>().messageController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Mesaj yazın…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // Send button
                    IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color: colorScheme.primary,
                      ),
                      onPressed: state.sending
                          ? null
                          : () async {
                        final chat = context.read<ChatManager>();
                        widget.logger.info('Send text button tapped. chatId={}', [widget.chatId]);
                        
                        try {
                          await chat.sendTextTo(widget.chatId);
                        } catch (e, st) {
                          widget.logger.err('Send text button handler failed. error={}', [e]);
                          if (kDebugMode) widget.logger.debug('Stack trace:\n{}', [st]);
                          
                          if (!context.mounted) return;
                          DialogUtils.openError(context, title: 'Mesaj Gönderim Hatası', message: 'Mesaj gönderilemedi.');
                        }
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Individual attachment option button for the expandable menu
class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
