import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

import '../constants/app_constants.dart';
import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

/// Service for handling Firebase Cloud Messaging (FCM)
/// 
/// Manages:
/// - FCM token lifecycle (save/refresh)
/// - Push notification permissions
/// - Foreground message display (in-app banner)
/// - Notification tap navigation
/// 
/// Note: FCM is NOT supported on Windows and Linux platforms.
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  
  // Lazy initialization of FirebaseMessaging to avoid errors on unsupported platforms
  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging get _messaging {
    _messagingInstance ??= FirebaseMessaging.instance;
    return _messagingInstance!;
  }
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ===== Notification Configuration Flags =====
  
  // --- In-App Notification Flags ---
  // These control whether in-app banners are shown when user is INSIDE the app.
  // Push notifications (when app is in background/terminated) are not affected.
  
  /// Whether to show in-app notification banners for chat messages.
  /// Set to false to disable the in-app banner while keeping push notifications.
  static const bool showInAppChatNotifications = true;
  
  /// Whether to show in-app notification banners for announcements/news.
  /// Set to false to disable the in-app banner while keeping push notifications.
  /// (Disabled by default since push notifications already alert the user)
  static const bool showInAppAnnouncementNotifications = false;
  
  // --- Logged-Out Notification Flags ---
  // These control whether notifications should be processed when user is logged out.
  // Set to false to prevent notifications from showing when user is not authenticated.
  
  /// Whether to allow chat notifications when user is logged out.
  /// When false, chat notifications are ignored if no user is authenticated.
  static const bool allowChatNotificationsWhenLoggedOut = false;
  
  /// Whether to allow announcement/news notifications when user is logged out.
  /// When false, announcement notifications are ignored if no user is authenticated.
  static const bool allowAnnouncementNotificationsWhenLoggedOut = false;

  /// Check if FCM is supported on this platform
  /// FCM is NOT supported on Windows and Linux
  static bool get isSupported {
    if (kIsWeb) return false; // Web has different FCM handling
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  // Currently active chat ID (to suppress notifications when already in that chat)
  String? _activeChatId;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  /// Returns false if FCM is not supported on this platform.
  Future<bool> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    if (!isSupported) {
      _logger.info('FCM is not supported on this platform, skipping initialization');
      return false;
    }

    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();
    
    // IMPORTANT: Disable system push notification when app is in foreground.
    // This prevents duplicate notifications (system + in-app banner).
    // We show our own in-app banner via _onForegroundMessage instead.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,  // Don't show notification alert
      badge: false,  // Don't update badge
      sound: false,  // Don't play sound
    );
    _logger.info('Foreground notification presentation disabled (using in-app banner instead)');

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();
    
    // Clear any existing badge count when app starts
    await clearBadge();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingMessage = initialMessage;
      _logger.info('App launched from notification: ${initialMessage.messageId}');
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
        _tryOpenPendingMessage();
      }
    });

    _logger.info('FCM service initialized');
    return true;
  }
  
  /// Clear the app icon badge count.
  /// 
  /// This should be called when:
  /// - App starts/initializes
  /// - App is resumed from background
  /// - User opens the relevant notification content
  /// 
  /// Works on iOS and Android (supported launchers).
  Future<void> clearBadge() async {
    if (!isSupported) return;
    
    try {
      // Check if badge is supported on this device
      final isSupported = await FlutterAppBadger.isAppBadgeSupported();
      if (!isSupported) {
        _logger.debug('App badge is not supported on this device');
        return;
      }
      
      await FlutterAppBadger.removeBadge();
      _logger.info('App badge cleared');
    } catch (e) {
      _logger.err('Error clearing app badge: $e');
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _logger.info('Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.err('Error requesting notification permissions: $e');
    }
  }

  /// Set up FCM message handlers
  void _setupMessageHandlers() {
    // Foreground messages - show in-app banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  /// Handle foreground messages - show in-app notification banner
  void _onForegroundMessage(RemoteMessage message) {
    _logger.info('Foreground message received: ${message.notification?.title}');

    // Check if user is logged in
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      // User is logged out - check if we should show this notification type
      final type = (message.data['type'] ?? '').toString();
      final isChatNotification = type == 'chat' || type == 'chat_admin';
      final isAnnouncementNotification = type == 'news';
      
      if (isChatNotification && !allowChatNotificationsWhenLoggedOut) {
        _logger.info('Ignoring chat notification - user is logged out');
        return;
      }
      if (isAnnouncementNotification && !allowAnnouncementNotificationsWhenLoggedOut) {
        _logger.info('Ignoring announcement notification - user is logged out');
        return;
      }
      // For other notification types when logged out, still skip
      if (!isChatNotification && !isAnnouncementNotification) {
        _logger.info('Ignoring notification - user is logged out');
        return;
      }
    }

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    // Check if we should suppress this notification (user is already viewing this chat)
    if (_shouldSuppressNotification(message.data)) {
      _logger.info('Suppressing notification - user is already in this chat');
      return;
    }

    // Check in-app notification flags based on notification type
    final type = (message.data['type'] ?? '').toString();
    final isChatNotification = type == 'chat' || type == 'chat_admin';
    final isAnnouncementNotification = type == 'news';
    
    if (isChatNotification && !showInAppChatNotifications) {
      _logger.info('Skipping in-app chat notification - disabled by flag');
      return;
    }
    if (isAnnouncementNotification && !showInAppAnnouncementNotifications) {
      _logger.info('Skipping in-app announcement notification - disabled by flag');
      return;
    }

    _showInAppNotification(
      context: context,
      title: notification.title ?? NotificationConstants.inAppNotificationDefaultTitle,
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Check if notification should be suppressed because user is already viewing the chat
  /// or because the current user is the sender of the message.
  bool _shouldSuppressNotification(Map<String, dynamic> data) {
    // Only suppress chat notifications
    final type = (data['type'] ?? '').toString();
    if (type != 'chat' && type != 'chat_admin') {
      return false;
    }

    final currentUserId = _auth.currentUser?.uid;
    
    // Suppress if the current user is the sender (they shouldn't receive their own message notification)
    final senderId = (data['senderId'] ?? '').toString();
    if (senderId.isNotEmpty && senderId == currentUserId) {
      _logger.info('Suppressing notification - current user is the sender');
      return true;
    }

    // Check if user is currently viewing this chat
    final notificationChatId = (data['chatId'] ?? '').toString();
    if (notificationChatId.isEmpty) {
      return false;
    }

    // Suppress if the notification is for the chat the user is currently viewing
    return _activeChatId != null && _activeChatId == notificationChatId;
  }

  /// Show in-app notification banner
  void _showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    // Remove existing banner if any
    _dismissCurrentBanner();

    // Get the overlay directly from the navigator state
    // (Overlay.of(context) fails because Navigator's context doesn't have Overlay as ancestor)
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _logger.warn('No overlay available for showing in-app notification');
      return;
    }

    // Determine notification type for color styling
    final type = (data['type'] ?? '').toString();
    final isNews = type == 'news';

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        backgroundColor: isNews 
            ? Color(NotificationConstants.newsNotificationBannerColor) 
            : Color(NotificationConstants.chatNotificationBannerColor),
        accentColor: isNews 
            ? Color(NotificationConstants.newsNotificationBannerAccentColor) 
            : Color(NotificationConstants.chatNotificationBannerAccentColor),
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: NotificationConstants.notificationDisplayTime), () {
      _dismissCurrentBanner();
    });
  }

  /// Dismiss current notification banner
  void _dismissCurrentBanner() {
    _currentBanner?.remove();
    _currentBanner = null;
  }

  /// Handle notification tap (from background/terminated state)
  void _onNotificationTap(RemoteMessage message) {
    _logger.info('Notification tapped: ${message.messageId}');
    
    // Check if user is logged in before processing notification tap
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      final type = (message.data['type'] ?? '').toString();
      final isChatNotification = type == 'chat' || type == 'chat_admin';
      final isAnnouncementNotification = type == 'news';
      
      if (isChatNotification && !allowChatNotificationsWhenLoggedOut) {
        _logger.info('Ignoring chat notification tap - user is logged out');
        clearBadge();
        return;
      }
      if (isAnnouncementNotification && !allowAnnouncementNotificationsWhenLoggedOut) {
        _logger.info('Ignoring announcement notification tap - user is logged out');
        clearBadge();
        return;
      }
    }
    
    _pendingMessage = message;
    _tryOpenPendingMessage();
    
    // Clear badge when user taps a notification
    clearBadge();
  }

  /// Try to open pending message (navigate to appropriate page)
  void _tryOpenPendingMessage() {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;
    final message = _pendingMessage;

    if (navigator == null || user == null || message == null) return;

    // Clear pending message to prevent double-open
    _pendingMessage = null;

    _handleNotificationTap(message.data);
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isAdmin = _adminUids.contains(user.uid);

    _logger.info('Handling notification tap: type=$type, isAdmin=$isAdmin');

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isAdmin) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatPage(overrideChatId: chatId),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const AdminChatListPage(),
            ));
          }
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ChatPage(),
          ));
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isAdmin) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatPage(overrideChatId: chatId),
          ));
        } else {
          navigator.push(MaterialPageRoute(
            builder: (_) => const AdminChatListPage(),
          ));
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    if (!isSupported) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user.
  /// Uses a single token per user (overwrites previous token).
  Future<void> saveFcmToken() async {
    if (!isSupported) return;
    
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token save');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.warn('Could not get FCM token');
        return;
      }

      _logger.info('FCM token obtained: ${token.substring(0, 20)}...');

      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'fcmToken': token,
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        final currentUser = _auth.currentUser;
        if (currentUser == null) return;
        
        await _firestore.collection('users').doc(currentUser.uid).set({
          'fcmToken': newToken,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Remove FCM token from Firestore for current user.
  /// Call this on logout to stop receiving notifications on this device.
  Future<void> removeFcmToken() async {
    if (!isSupported) return;
    
    final user = _auth.currentUser;
    if (user == null) {
      _logger.info('No user logged in, skipping FCM token removal');
      return;
    }

    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      await userDoc.set({
        'fcmToken': FieldValue.delete(),
      }, SetOptions(merge: true));

      _logger.info('FCM token removed for user ${user.uid}');
    } catch (e) {
      _logger.err('Error removing FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);

  /// Set the currently active chat ID.
  /// Call this when entering a chat page to suppress notifications for that chat.
  void setActiveChatId(String? chatId) {
    _activeChatId = chatId;
    _logger.info('Active chat set to: $chatId');
  }

  /// Clear the active chat ID.
  /// Call this when leaving a chat page.
  void clearActiveChatId() {
    _logger.info('Active chat cleared (was: $_activeChatId)');
    _activeChatId = null;
  }

  /// Get the currently active chat ID (for debugging/testing).
  String? get activeChatId => _activeChatId;
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final Color backgroundColor;
  final Color accentColor;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
    this.backgroundColor = const Color(0xFF075E54),
    this.accentColor = const Color(0xFF25D366),
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  widget.onDismiss();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main content area (tappable)
                    InkWell(
                      onTap: widget.onTap,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            // App icon / avatar - Company logo
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                NotificationConstants.inAppNotificationIconAsset,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title and message
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.body,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),
                    // Action buttons row
                    Row(
                      children: [
                        // "Kapat" (Dismiss) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: const Text(
                                'Kapat',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Vertical divider
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        // "Aç" (Open) button
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: widget.accentColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

