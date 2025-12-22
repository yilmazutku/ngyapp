# In-app notification overlay issue
_Exported on 12/18/2025 at 11:10:43 GMT+3 from Cursor (2.2.29)_

---

**User**

I tried to get notifications in my app when admin sent a message. I was logged in as a client, a non-admin. Here is the stadck i got: [_ChatPageState] [2025-12-18 09:58:20.299] [INFO] [_ChatPageState] ChatPage disposed. currentUid=lRxCbZvX7ffcpdxr8kvPCnCLYfG2
I/MESA    ( 4963): exportSyncFdForQSRILocked: call for image 0x7104b6ca8190 hos timage handle 0x70002000000dd
I/MESA    ( 4963): exportSyncFdForQSRILocked: got fd: 243
D/FLTFireMsgReceiver( 4963): broadcast received for message
[FcmService] [2025-12-18 09:59:53.717] [INFO] [FcmService] Foreground message received: Destek
E/flutter ( 4963): [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: No Overlay widget found.
E/flutter ( 4963): Some widgets require an Overlay widget ancestor for correct operation.
E/flutter ( 4963): The most common way to add an Overlay to an application is to include a MaterialApp, CupertinoApp or Navigator widget in the runApp() call.
E/flutter ( 4963): The context from which that widget was searching for an overlay was:
E/flutter ( 4963):   Navigator-[LabeledGlobalKey<NavigatorState>#3d4de]
E/flutter ( 4963): #0      Overlay.of.<anonymous closure> (package:flutter/src/widgets/overlay.dart:560:9)
E/flutter ( 4963): #1      Overlay.of (package:flutter/src/widgets/overlay.dart:563:6)
E/flutter ( 4963): #2      FcmService._showInAppNotification (package:untitled/services/fcm_service.dart:141:29)
E/flutter ( 4963): #3      FcmService._onForegroundMessage (package:untitled/services/fcm_service.dart:123:5)
E/flutter ( 4963): #4      _RootZone.runUnaryGuarded (dart:async/zone.dart:1609:10)
E/flutter ( 4963): #5      _BufferingStreamSubscription._sendData (dart:async/stream_impl.dart:366:11)
E/flutter ( 4963): #6      _DelayedData.perform (dart:async/stream_impl.dart:542:14)
E/flutter ( 4963): #7      _PendingEvents.handleNext (dart:async/stream_impl.dart:647:11)
E/flutter ( 4963): #8      _PendingEvents.schedule.<anonymous closure> (dart:async/stream_impl.dart:618:7)
E/flutter ( 4963): #9      _microtaskLoop (dart:async/schedule_microtask.dart:40:21)
E/flutter ( 4963): #10     _startMicrotaskLoop (dart:async/schedule_microtask.dart:49:5)
E/flutter ( 4963):  The things u gotta check exist at @lib/services/fcm_service.dart 

---

**Cursor**

```plaintext
No Overlay widget found.
Some widgets require an Overlay widget ancestor for correct operation.
The most common way to add an Overlay to an application is to include a MaterialApp, CupertinoApp or Navigator widget in the runApp() call.
The context from which that widget was searching for an overlay was:
  Navigator-[LabeledGlobalKey<NavigatorState>#3d4de]
```

```dart
void _showInAppNotification({
  required BuildContext context,
  required String title,
  required String body,
  required Map<String, dynamic> data,
}) {
  // Remove existing banner if any
  _dismissCurrentBanner();

  final overlay = Overlay.of(context);  // Line 141 - this is failing
  ...
}
```

```dart
void _onForegroundMessage(RemoteMessage message) {
  _logger.info('Foreground message received: ${message.notification?.title}');

  final context = _navigatorKey?.currentContext;  // This is the Navigator's context
  if (context == null) {
    _logger.warn('No context available for showing in-app notification');
    return;
  }
  ...
}
```

Looking at the error, the issue is that `Overlay.of(context)` is being called with the Navigator's context, but the Overlay is a child of the Navigator, not an ancestor. This causes the "No Overlay widget found" error.

The fix is to get the overlay directly from the NavigatorState instead of searching for it in the widget tree.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';

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
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final Logger _logger = Logger.forClass(FcmService);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Admin UIDs for routing notifications
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pending message to open (when app launched from notification)
  RemoteMessage? _pendingMessage;

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  Future<void> initialize({required GlobalKey<NavigatorState> navigatorKey}) async {
    _navigatorKey = navigatorKey;
    _logger.info('Initializing FCM service');

    // Request notification permissions
    await _requestPermissions();

    // Set up message handlers
    _setupMessageHandlers();

    // Save token for current user (if logged in)
    await saveFcmToken();

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

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _logger.warn('No context available for showing in-app notification');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _showInAppNotification(
      context: context,
      title: notification.title ?? 'Bildirim',
      body: notification.body ?? '',
      data: message.data,
    );
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

    _currentBanner = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        onTap: () {
          _dismissCurrentBanner();
          _handleNotificationTap(data);
        },
        onDismiss: _dismissCurrentBanner,
      ),
    );

    overlay.insert(_currentBanner!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
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
    _pendingMessage = message;
    _tryOpenPendingMessage();
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

      default:
        _logger.warn('Unknown notification type: $type');
    }
  }

  /// Try opening pending message after first frame
  /// Call this in main() after runApp() using addPostFrameCallback
  void tryOpenPendingMessageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryOpenPendingMessage();
    });
  }

  /// Save FCM token to Firestore for current user
  Future<void> saveFcmToken() async {
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
        'tokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      _logger.info('FCM token saved for user ${user.uid}');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.info('FCM token refreshed');
        await userDoc.set({
          'tokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      _logger.err('Error saving FCM token: $e');
    }
  }

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);
}

/// In-app notification banner widget (WhatsApp-style)
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
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
                  color: const Color(0xFF075E54), // WhatsApp dark green
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
                            // App icon / avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366), // WhatsApp green
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.chat,
                                color: Colors.white,
                                size: 22,
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
                              child: const Text(
                                'Aç',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF25D366), // WhatsApp green
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


```

Fixed! The issue was that `Overlay.of(context)` searches for an Overlay widget **above** the given context in the widget tree. However, the context from `_navigatorKey?.currentContext` is the Navigator's own context, and the Overlay is actually a **child** of the Navigator, not an ancestor.

The fix uses `_navigatorKey?.currentState?.overlay` which directly accesses the Navigator's internal overlay without searching the widget tree.

---

**User**

when app is in bg, i dont see sliding notification widget when im in home screen on the emulated device. but when i scroll down to see all notifications i see it there. is there a fix for this

---

**Cursor**

This is about Android notification channels. For notifications to appear as "heads-up" (sliding) notifications on the home screen, the notification channel needs to have **high importance**. By default, Firebase creates a channel with default importance which only shows in the notification shade.

Let me check if there's any notification channel configuration in your project:

The notification channel is already set to `IMPORTANCE_HIGH`. Let me check your Cloud Functions to see if the notification is being sent with the right priority:

```javascript
android: {
  priority: 'high', // This is correct placement
  notification: {
    channelId: CHAT_CHANNEL_ID,
    // ...
  },
}
```

```javascript
function buildAndroidConfig(title, body) {
  return {
    priority: 'high',
    notification: {
      channelId: CHAT_CHANNEL_ID,
      // ...
    },
  };
}
```

I found the issue! Your Cloud Functions config has `priority: 'high'` which controls **delivery priority** (how fast the message arrives), but for **heads-up/pop-up notifications**, you need to set `notificationPriority` inside the notification object.

Also, since the notification channel was likely created before with default importance, Android caches those settings. You have two options:

**Option 1:** Update Cloud Functions to force high notification priority (recommended):

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notification channel ID (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon (optional, uses app icon if not set)
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // Display priority - enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @return {object} APNs config.
 */
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        sound: 'default',
        badge: 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin should open ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

```

Now you need to deploy the updated Cloud Functions. But there's another important issue:

**Android caches notification channel settings.** If the channel was created before with lower importance, changing the code won't help - the old settings persist on the device.

**Quick fix: Uninstall and reinstall the app** on the emulator/device to clear the cached channel settings.

**Or, create a new channel ID** (this forces Android to create a fresh channel):

Let me update the channel ID to force a fresh channel with correct settings:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Default FCM notification channel -->
    <string name="notification_channel_id" translatable="false">chat_messages_v2</string>
    
    <!-- Chat notifications channel settings -->
    <string name="chat_channel_name">Sohbet Mesajları</string>
    <string name="chat_channel_description">Yeni sohbet mesajı bildirimleri</string>
</resources>
```

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notification channel ID (must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon (optional, uses app icon if not set)
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // Display priority - enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @return {object} APNs config.
 */
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        sound: 'default',
        badge: 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin should open ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

```

Done! Here's what I changed:

### Changes Made:
1. **`functions/index.js`**: Added `notificationPriority: 'PRIORITY_MAX'` to enable heads-up notifications
2. **Channel ID updated to `chat_messages_v2`** in both:
   - `android/app/src/main/res/values/string.xml`
   - `functions/index.js`

### What You Need to Do:

1. **Deploy the updated Cloud Functions:**
   ```bash
   cd functions
   firebase deploy --only functions
   ```

2. **Rebuild and reinstall the app** on your emulator/device:
   ```bash
   flutter run
   ```

The new channel ID (`chat_messages_v2`) will create a fresh notification channel with `IMPORTANCE_HIGH`, and the `notificationPriority: 'PRIORITY_MAX'` ensures the notification appears as a heads-up even if the channel settings somehow get cached wrong.

```shellscript
   cd functions
   firebase deploy --only functions
```

```shellscript
   flutter run
```

---

**User**

C:\Users\utku.yilmaz\ilkappv1\functions\.eslintrc.js
  14:9   error  Missing space before value for key 'rules'    key-spacing
  15:1   error  Expected indentation of 4 spaces but found 6  indent
  15:7   error  Strings must use singlequote                  quotes
  15:27  error  Missing trailing comma                        comma-dangle
  16:1   error  Expected indentation of 2 spaces but found 4  indent
  16:6   error  Missing trailing comma                        comma-dangle

C:\Users\utku.yilmaz\ilkappv1\functions\index.js
  57:9  error  Inconsistently quoted property 'sound' found  quote-props
  58:9  error  Inconsistently quoted property 'badge' found  quote-props


---

**Cursor**

```javascript
module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    'eslint:recommended',
    'google',
  ],
  parserOptions: {
    ecmaVersion: 2020,
  },
  rules: {
    'linebreak-style': 0,
  },
};

```

```javascript
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');

admin.initializeApp();

const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
]);

// Notif(must match Android string.xml: notification_channel_id)
const CHAT_CHANNEL_ID = 'chat_messages_v2';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: 'ic_notification', // Custom icon-optional, uses app icon if unset
      color: '#075E54', // WhatsApp green
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @return {object} APNs config.
 */
function buildApnsConfig() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      let tokens = [];
      if (userData && Array.isArray(userData.tokens)) {
        tokens = userData.tokens;
      }
      if (tokens.length === 0) return;

      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      const title = 'Destek';
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        await admin.firestore()
            .collection('users')
            .doc(chatId)
            .set(
                {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                {merge: true},
            );
      }
    },
);
/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect all admin tokens (both admins)
      const allAdminTokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData && Array.isArray(adminData.tokens)) {
          allAdminTokens.push(...adminData.tokens);
        }
      }

      // Deduplicate tokens
      const tokens = Array.from(new Set(allAdminTokens));
      if (tokens.length === 0) return;

      // Notification body
      let body = 'Yeni mesaj';
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = 'Fotoğraf';
      }

      // Try to get user's name for better notification title
      let title = 'Kullanıcı mesajı';
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Optional cleanup: remove dead tokens from admin docs
      const invalid = [];
      res.responses.forEach((r, i) => {
        if (r.success) return;

        const code = (r.error && r.error.code) ? r.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        if (isInvalid) invalid.push(tokens[i]);
        logger.warn('FCM send failed', {code: code});
      });

      if (invalid.length) {
        for (const adminUid of ADMIN_UIDS) {
          await admin.firestore()
              .collection('users')
              .doc(adminUid)
              .set(
                  {tokens: admin.firestore.FieldValue.arrayRemove(...invalid)},
                  {merge: true},
              );
        }
      }
    },
);

```

Fixed both ESLint errors:

1. **`.eslintrc.js`** - Fixed spacing, indentation (2 spaces), single quotes, and trailing commas
2. **`index.js`** - Quoted `sound` and `badge` properties to be consistent with other quoted properties (`'mutable-content'`, `'content-available'`)

---

**User**

now, make a seperate file/folder whatever u need to handle the notifications on an iOs device. Do the same steps for a MACOS device aswell. While we do this, its good to make a file that keeps our platform specific stuff, like a strategy pattern application, to apply which config files in the main.dart file, so we can keep a clear track of what goes on. 

---

**Cursor**

I'll help you create a platform-specific notification system with a strategy pattern. Let me first explore the current structure:

Now I'll create a platform-specific notification system with a strategy pattern. Let me set up the structure:

```dart
import 'package:flutter/widgets.dart';

/// Abstract interface for platform-specific configurations.
/// 
/// Implements the Strategy Pattern to handle platform-specific
/// initialization and notification setup.
abstract class PlatformConfig {
  /// Platform display name for logging
  String get platformName;

  /// Whether push notifications are supported on this platform
  bool get supportsPushNotifications;

  /// Whether local notifications are supported on this platform
  bool get supportsLocalNotifications;

  /// Initialize platform-specific services
  /// 
  /// Called during app startup before runApp()
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  });

  /// Configure push notifications for this platform
  /// 
  /// This includes:
  /// - Requesting permissions
  /// - Setting up notification channels/categories
  /// - Configuring foreground presentation options
  Future<void> configurePushNotifications();

  /// Configure local notifications for this platform
  Future<void> configureLocalNotifications();

  /// Clean up platform-specific resources
  Future<void> dispose();
}

```

```dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import 'platform_config.dart';
import 'platform_config_android.dart';
import 'platform_config_ios.dart';
import 'platform_config_macos.dart';
import 'platform_config_stub.dart';

/// Factory for creating platform-specific configurations.
/// 
/// Uses the Factory Pattern to instantiate the correct platform
/// config based on the current runtime platform.
class PlatformConfigFactory {
  static final Logger _logger = Logger.forClass(PlatformConfigFactory);

  /// Get the appropriate platform configuration
  static PlatformConfig create() {
    if (kIsWeb) {
      _logger.info('Creating Web platform config (stub - no push notifications)');
      return StubPlatformConfig(platformName: 'Web');
    }

    if (Platform.isAndroid) {
      _logger.info('Creating Android platform config');
      return AndroidPlatformConfig();
    }

    if (Platform.isIOS) {
      _logger.info('Creating iOS platform config');
      return IosPlatformConfig();
    }

    if (Platform.isMacOS) {
      _logger.info('Creating macOS platform config');
      return MacosPlatformConfig();
    }

    if (Platform.isWindows) {
      _logger.info('Creating Windows platform config (stub - no push notifications)');
      return StubPlatformConfig(platformName: 'Windows');
    }

    if (Platform.isLinux) {
      _logger.info('Creating Linux platform config (stub - no push notifications)');
      return StubPlatformConfig(platformName: 'Linux');
    }

    _logger.warn('Unknown platform, using stub config');
    return StubPlatformConfig(platformName: 'Unknown');
  }

  /// Initialize platform-specific services
  /// 
  /// Convenience method that creates and initializes the config in one call.
  static Future<PlatformConfig> initializePlatform({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    final config = create();
    await config.initialize(navigatorKey: navigatorKey);
    return config;
  }
}

```

```dart
import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import 'platform_config.dart';

/// Stub implementation for platforms without push notification support.
/// 
/// Used for:
/// - Web (limited FCM support, handled differently)
/// - Windows (no FCM support)
/// - Linux (no FCM support)
class StubPlatformConfig implements PlatformConfig {
  final Logger _logger = Logger.forClass(StubPlatformConfig);

  @override
  final String platformName;

  StubPlatformConfig({required this.platformName});

  @override
  bool get supportsPushNotifications => false;

  @override
  bool get supportsLocalNotifications => false;

  @override
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _logger.info('$platformName: Platform initialized (no push notification support)');
  }

  @override
  Future<void> configurePushNotifications() async {
    _logger.info('$platformName: Push notifications not supported on this platform');
  }

  @override
  Future<void> configureLocalNotifications() async {
    _logger.info('$platformName: Local notifications not supported on this platform');
  }

  @override
  Future<void> dispose() async {
    _logger.info('$platformName: Platform resources disposed');
  }
}

```

```dart
import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import '../services/fcm_service.dart';
import 'platform_config.dart';

/// Android-specific platform configuration.
/// 
/// Handles:
/// - FCM push notifications (via FcmService)
/// - Notification channels are created in native code (MyApplication.kt)
class AndroidPlatformConfig implements PlatformConfig {
  final Logger _logger = Logger.forClass(AndroidPlatformConfig);

  GlobalKey<NavigatorState>? _navigatorKey;

  @override
  String get platformName => 'Android';

  @override
  bool get supportsPushNotifications => true;

  @override
  bool get supportsLocalNotifications => true;

  @override
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;
    _logger.info('Android platform initializing...');

    // Configure notifications
    await configurePushNotifications();
    await configureLocalNotifications();

    _logger.info('Android platform initialized');
  }

  @override
  Future<void> configurePushNotifications() async {
    _logger.info('Configuring Android push notifications...');

    // Initialize FCM service
    // Notification channels are created in native Android code (MyApplication.kt)
    // Channel ID: chat_messages_v2 with IMPORTANCE_HIGH
    await FcmService().initFcmService(navigatorKey: _navigatorKey!);

    _logger.info('Android push notifications configured');
  }

  @override
  Future<void> configureLocalNotifications() async {
    _logger.info('Android local notifications configured via flutter_local_notifications');
    // Local notifications are handled by NotificationService
    // Channel configuration is done in native code
  }

  @override
  Future<void> dispose() async {
    _logger.info('Android platform resources disposed');
  }
}

```

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import '../services/fcm_service.dart';
import 'platform_config.dart';

/// iOS-specific platform configuration.
/// 
/// Handles:
/// - FCM push notifications with APNs
/// - Foreground notification presentation options
/// - Notification permission requests
/// 
/// Native setup required:
/// - Enable Push Notifications capability in Xcode
/// - Enable Background Modes > Remote notifications
/// - Upload APNs key to Firebase Console
class IosPlatformConfig implements PlatformConfig {
  final Logger _logger = Logger.forClass(IosPlatformConfig);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  GlobalKey<NavigatorState>? _navigatorKey;

  @override
  String get platformName => 'iOS';

  @override
  bool get supportsPushNotifications => true;

  @override
  bool get supportsLocalNotifications => true;

  @override
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;
    _logger.info('iOS platform initializing...');

    // Configure notifications
    await configurePushNotifications();
    await configureLocalNotifications();

    _logger.info('iOS platform initialized');
  }

  @override
  Future<void> configurePushNotifications() async {
    _logger.info('Configuring iOS push notifications...');

    // Set foreground notification presentation options
    // This controls how notifications appear when the app is in foreground
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, // Show alert banner
      badge: true, // Update app badge
      sound: true, // Play sound
    );
    _logger.info('iOS foreground presentation options set');

    // Request notification permissions
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false, // Request full authorization, not provisional
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );
    _logger.info('iOS notification permission: ${settings.authorizationStatus}');

    // Get APNs token (iOS-specific)
    try {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null) {
        _logger.info('APNs token obtained: ${apnsToken.substring(0, 20)}...');
      } else {
        _logger.warn('APNs token is null - push notifications may not work');
      }
    } catch (e) {
      _logger.err('Failed to get APNs token: $e');
    }

    // Initialize FCM service (handles token save, message handlers, etc.)
    await FcmService().initFcmService(navigatorKey: _navigatorKey!);

    _logger.info('iOS push notifications configured');
  }

  @override
  Future<void> configureLocalNotifications() async {
    _logger.info('iOS local notifications configured via flutter_local_notifications');
    // Local notifications are handled by NotificationService
  }

  @override
  Future<void> dispose() async {
    _logger.info('iOS platform resources disposed');
  }
}

```

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import '../services/fcm_service.dart';
import 'platform_config.dart';

/// macOS-specific platform configuration.
/// 
/// Handles:
/// - FCM push notifications with APNs
/// - Foreground notification presentation options
/// - Notification permission requests
/// 
/// Native setup required:
/// - Enable Push Notifications capability in Xcode
/// - Enable Background Modes > Remote notifications (if available)
/// - Upload APNs key to Firebase Console
/// - Add network client entitlement
/// - Sign app with proper provisioning profile
class MacosPlatformConfig implements PlatformConfig {
  final Logger _logger = Logger.forClass(MacosPlatformConfig);
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  GlobalKey<NavigatorState>? _navigatorKey;

  @override
  String get platformName => 'macOS';

  @override
  bool get supportsPushNotifications => true;

  @override
  bool get supportsLocalNotifications => true;

  @override
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;
    _logger.info('macOS platform initializing...');

    // Configure notifications
    await configurePushNotifications();
    await configureLocalNotifications();

    _logger.info('macOS platform initialized');
  }

  @override
  Future<void> configurePushNotifications() async {
    _logger.info('Configuring macOS push notifications...');

    // Set foreground notification presentation options
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, // Show alert banner in Notification Center
      badge: true, // Update dock badge
      sound: true, // Play sound
    );
    _logger.info('macOS foreground presentation options set');

    // Request notification permissions
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );
    _logger.info('macOS notification permission: ${settings.authorizationStatus}');

    // Get APNs token (macOS also uses APNs like iOS)
    try {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null) {
        _logger.info('APNs token obtained: ${apnsToken.substring(0, 20)}...');
      } else {
        _logger.warn('APNs token is null - push notifications may not work');
        _logger.warn('Ensure app is signed with Push Notifications capability');
      }
    } catch (e) {
      _logger.err('Failed to get APNs token: $e');
    }

    // Initialize FCM service
    await FcmService().initFcmService(navigatorKey: _navigatorKey!);

    _logger.info('macOS push notifications configured');
  }

  @override
  Future<void> configureLocalNotifications() async {
    _logger.info('macOS local notifications configured via flutter_local_notifications');
    // Local notifications are handled by NotificationService
  }

  @override
  Future<void> dispose() async {
    _logger.info('macOS platform resources disposed');
  }
}

```

Now let me update the iOS native files for push notification support:

```swift
import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase
    FirebaseApp.configure()
    
    // Set up push notifications
    configureNotifications(application: application)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  /// Configure push notification settings
  private func configureNotifications(application: UIApplication) {
    // Set messaging delegate
    Messaging.messaging().delegate = self
    
    // Set notification delegate for foreground notifications
    UNUserNotificationCenter.current().delegate = self
    
    // Register for remote notifications
    application.registerForRemoteNotifications()
  }
  
  // MARK: - Remote Notifications
  
  /// Called when APNs has assigned a device token
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Pass device token to Firebase Messaging
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
  
  /// Called when APNs registration fails
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("Failed to register for remote notifications: \(error.localizedDescription)")
  }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
  /// Called when FCM token is refreshed
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("FCM token received: \(fcmToken ?? "nil")")
    
    // Token is automatically handled by Flutter FCM plugin
    // but you can use this for native-side token handling if needed
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate {
  /// Handle notification when app is in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("Foreground notification received: \(userInfo)")
    
    // Show notification even when app is in foreground
    // This is controlled by Flutter side via setForegroundNotificationPresentationOptions
    // but we provide a fallback here
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .badge, .sound]])
    } else {
      completionHandler([[.alert, .badge, .sound]])
    }
  }
  
  /// Handle notification tap
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("Notification tapped: \(userInfo)")
    
    // This is handled by Flutter FCM plugin
    completionHandler()
  }
}

```

```plaintext
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Untitled</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>untitled</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<!-- Push Notifications -->
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>remote-notification</string>
	</array>
	<!-- Firebase Messaging -->
	<key>FirebaseMessagingAutoInitEnabled</key>
	<true/>
</dict>
</plist>

```

```swift
import Cocoa
import FlutterMacOS
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@NSApplicationMain
class AppDelegate: FlutterAppDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Configure Firebase
    FirebaseApp.configure()
    
    // Set up push notifications
    configureNotifications()
    
    super.applicationDidFinishLaunching(notification)
  }
  
  /// Configure push notification settings
  private func configureNotifications() {
    // Set messaging delegate
    Messaging.messaging().delegate = self
    
    // Set notification delegate for foreground notifications
    UNUserNotificationCenter.current().delegate = self
    
    // Register for remote notifications
    NSApplication.shared.registerForRemoteNotifications()
  }
  
  // MARK: - Remote Notifications
  
  override func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Pass device token to Firebase Messaging
    Messaging.messaging().apnsToken = deviceToken
  }
  
  override func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register for remote notifications: \(error.localizedDescription)")
  }
  
  // MARK: - MessagingDelegate
  
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("FCM token received: \(fcmToken ?? "nil")")
    
    // Token is automatically handled by Flutter FCM plugin
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
  
  // MARK: - UNUserNotificationCenterDelegate
  
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("Foreground notification received: \(userInfo)")
    
    // Show notification even when app is in foreground
    if #available(macOS 11.0, *) {
      completionHandler([[.banner, .badge, .sound]])
    } else {
      completionHandler([[.alert, .badge, .sound]])
    }
  }
  
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("Notification tapped: \(userInfo)")
    
    // This is handled by Flutter FCM plugin
    completionHandler()
  }
}

```

```plaintext
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>aps-environment</key>
	<string>development</string>
</dict>
</plist>

```

```plaintext
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>aps-environment</key>
	<string>production</string>
</dict>
</plist>

```

```plaintext
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIconFile</key>
	<string></string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>NSHumanReadableCopyright</key>
	<string>$(PRODUCT_COPYRIGHT)</string>
	<key>NSMainNibFile</key>
	<string>MainMenu</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<!-- Firebase Messaging -->
	<key>FirebaseMessagingAutoInitEnabled</key>
	<true/>
</dict>
</plist>

```

Now let me update `main.dart` to use the platform config system:

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize FCM service (handles permissions, token, message handlers)
  await FcmService().initFcmService(navigatorKey: navKey);

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize FCM service (handles permissions, token, message handlers)
  await FcmService().initFcmService(navigatorKey: navKey);

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

```dart
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:untitled/pages/admin_chat_page.dart';
import 'package:untitled/pages/chat_page_new.dart';
import 'package:untitled/providers/chat_manager_new.dart';
import 'package:untitled/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'tabs/admin_images_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = true;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {
  logger.info('Application started');
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');

  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Uncomment the line below for testing auto-login; remove for production
  await signInAutomatically();

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame
  FcmService().tryOpenPendingMessageAfterFrame();
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.green),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
          // home: StreamBuilder<User?>(
          //   stream: FirebaseAuth.instance.authStateChanges(),
          //   builder: (context, snapshot) {
          //     logger.info(
          //       'authStateChanges: connectionState=${snapshot.connectionState}, '
          //           'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
          //     );
          //
          //     if (snapshot.connectionState == ConnectionState.waiting) {
          //       return const Center(child: CircularProgressIndicator());
          //     }
          //     if (snapshot.hasData) {
          //       logger.info('User is logged in, showing HomePage');
          //       return const HomePage();
          //     }
          //     logger.info('No user logged in, showing LoginPage');
          //     return const LoginPage();
          //   },
          // ),
        ),
      ),
    );
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        // final isAdmin = role == 'admin';
        const isAdmin = true;

        // List of grid items for all users
        final List<Map<String, dynamic>> gridItems = [
          {
            'icon': Icons.food_bank,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, FcmService.isAdmin(userId)),
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
        ];

        // Add admin-specific items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'],
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

```

```dart
/// Platform-specific configuration exports.
/// 
/// This module provides a Strategy Pattern implementation for handling
/// platform-specific initialization, particularly for push notifications.
/// 
/// Usage in main.dart:
/// ```dart
/// import 'platform/platform_config_factory.dart';
/// 
/// void main() async {
///   // ...
///   platformConfig = await PlatformConfigFactory.initializePlatform(
///     navigatorKey: navKey,
///   );
/// }
/// ```

export 'platform_config.dart';
export 'platform_config_android.dart';
export 'platform_config_factory.dart';
export 'platform_config_ios.dart';
export 'platform_config_macos.dart';
export 'platform_config_stub.dart';

```

Done! Here's a summary of the platform-specific notification system I created:

## New Structure: `lib/platform/`

| File | Purpose |
|------|---------|
| `platform_config.dart` | Abstract interface defining platform capabilities |
| `platform_config_factory.dart` | Factory that selects the right config based on platform |
| `platform_config_android.dart` | Android-specific setup (uses native notification channels) |
| `platform_config_ios.dart` | iOS-specific setup (APNs, foreground presentation) |
| `platform_config_macos.dart` | macOS-specific setup (APNs, entitlements) |
| `platform_config_stub.dart` | Stub for platforms without push support (Web, Windows, Linux) |
| `platform.dart` | Barrel file for easy imports |

## Native Files Updated

### iOS
- **`ios/Runner/AppDelegate.swift`** - Firebase + APNs configuration, foreground handling
- **`ios/Runner/Info.plist`** - Added `UIBackgroundModes` for remote notifications

### macOS
- **`macos/Runner/AppDelegate.swift`** - Firebase + APNs configuration
- **`macos/Runner/DebugProfile.entitlements`** - Added `aps-environment: development`
- **`macos/Runner/Release.entitlements`** - Added `aps-environment: production`
- **`macos/Runner/Info.plist`** - Added Firebase auto-init

## How It Works (Strategy Pattern)

```
main.dart
    │
    ▼
PlatformConfigFactory.initializePlatform()
    │
    ├── Android? → AndroidPlatformConfig
    ├── iOS?     → IosPlatformConfig
    ├── macOS?   → MacosPlatformConfig
    └── Other?   → StubPlatformConfig
```

## Additional iOS/macOS Setup Required

For push notifications to work on real devices, you still need to:

1. **In Xcode (iOS/macOS):**
   - Enable "Push Notifications" capability
   - Enable "Background Modes" → "Remote notifications"
   - Sign with a provisioning profile that has Push Notifications enabled

2. **In Firebase Console:**
   - Upload your APNs Authentication Key (.p8 file)
   - Or upload APNs Certificate (.p12 file)

```plaintext
main.dart
    │
    ▼
PlatformConfigFactory.initializePlatform()
    │
    ├── Android? → AndroidPlatformConfig
    ├── iOS?     → IosPlatformConfig
    ├── macOS?   → MacosPlatformConfig
    └── Other?   → StubPlatformConfig
```

