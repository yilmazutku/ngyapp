// lib/pages/chat_page_new.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

class _ChatPageState extends State<ChatPage> {
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
    
    _currentUid = FirebaseAuth.instance.currentUser!.uid;
    
    // Resolve chat ID once and cache it
    _chatId = widget.overrideChatId ?? _currentUid;
    
    // Determine if current user is an admin
    _isAdminUser = ChatManager.isAdminUid(_currentUid);
    
    // Meal upload is available for all users
    _canUploadMeals = true;
    
    // Set active chat ID to suppress notifications for this chat
    FcmService().setActiveChatId(_chatId);
    
    logger.info(
      'ChatPage initialized. currentUid={} isAdmin={} chatId={} canUploadMeals={}',
      [_currentUid, _isAdminUser, _chatId, _canUploadMeals]
    );
  }

  @override
  void dispose() {
    // Clear active chat ID to resume receiving notifications
    FcmService().clearActiveChatId();
    logger.info('ChatPage disposed. currentUid={}', [_currentUid]);
    super.dispose();
  }

  /// Pick an image from the gallery and send it to the chat.
  /// 
  /// Flow:
  /// 1. Opens gallery picker
  /// 2. Shows loading dialog during upload
  /// 3. Sends image via ChatManager
  /// 4. Handles errors with user-friendly dialogs
  Future<void> _pickAndSendImage() async {
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
        title: Text(PushNotificationReference.chatAdminToUserTitle),
        // Show chat user name in subtitle if admin is viewing another user's chat
        bottom: widget.overrideChatId != null && _isAdminUser
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: _buildUserNameSubtitle(_chatId),
              )
            : null,
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

  /// Build a subtitle widget displaying the user's full name.
  /// 
  /// Fetches user details from Firestore and displays name + surname.
  /// Shows a loading indicator while fetching, and falls back to UID on error.
  Widget _buildUserNameSubtitle(String userId) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    
    return FutureBuilder(
      future: userProvider.fetchUserDetails(userId: userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          );
        }
        
        String displayName = userId; // Fallback to UID
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          final firstName = user.name.trim();
          final lastName = user.surname.trim() ?? '';
          displayName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
          logger.debug('User name loaded for chatId={}: {}', [userId, displayName]);
        } else if (snapshot.hasError) {
          logger.warn('Failed to load user name for chatId={}: {}', [userId, snapshot.error]);
        }
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Kullanıcı: $displayName',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
class _ChatInputRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        // Only rebuild when sending/uploading state changes
        child: Selector<ChatManager, ({bool sending, bool uploading})>(
          selector: (_, chat) => (sending: chat.sending, uploading: chat.isUploading),
          builder: (context, state, _) {
            final isDisabled = state.sending || state.uploading;
            
            return Row(
              children: [
                // Gallery image button
                IconButton(
                  icon: const Icon(Icons.photo),
                  onPressed: isDisabled ? null : onPickImage,
                  tooltip: 'Galeriden görsel',
                ),

                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: isDisabled ? null : onCaptureImage,
                  tooltip: 'Kameradan çek',
                ),

                // Meal upload button
                if (canUploadMeals)
                  TextButton.icon(
                    onPressed: isDisabled ? null : onMealUpload,
                    icon: const Icon(Icons.restaurant),
                    label: const Text('Öğün Yükle'),
                  ),
                
                const SizedBox(width: 8),
                
                // Text input field
                Expanded(
                  child: TextField(
                    controller: context.read<ChatManager>().messageController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yazın…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Send button
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: state.sending
                      ? null
                      : () async {
                    final chat = context.read<ChatManager>();
                    logger.info('Send text button tapped. chatId={}', [chatId]);
                    
                    try {
                      await chat.sendTextTo(chatId);
                    } catch (e, st) {
                      logger.err('Send text button handler failed. error={}', [e]);
                      if (kDebugMode) logger.debug('Stack trace:\n{}', [st]);
                      
                      if (!context.mounted) return;
                      DialogUtils.openError(context, title: 'Mesaj Gönderim Hatası', message: 'Mesaj gönderilemedi.');
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
