import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:app_badge_plus/app_badge_plus.dart';

import '../constants/app_constants.dart';
import '../pages/admin_chat_page.dart';
import '../pages/chat_page_new.dart';
import '../news/news_list_page.dart';
import '../providers/chat_manager_new.dart';
import 'notification_tap_gate.dart';
import 'open_chats.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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

  // Lazy initialization of FirebaseMessaging to avoid errors on unsupported platforms
  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging get _messaging {
    _messagingInstance ??= FirebaseMessaging.instance;
    return _messagingInstance!;
  }
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Registered once. saveFcmToken() runs again on every login, so subscribing
  /// from there stacked a new listener per login and wrote the refreshed token
  /// once per stacked listener.
  StreamSubscription<String>? _tokenRefreshSub;

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

  /// Check if FCM is supported on this platform (not on Windows)
  ///
  /// FCM jetonu yalnızca burada desteklenen platformlarda (Android, iOS,
  /// macOS) okunur, yazılır ve silinir; Windows ve Linux'ta kullanıcı
  /// kaydındaki jetona hiç dokunulmaz.
  static bool get isSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  // Admin UIDs (Yönetici Tarafı); chat notifications follow
  // ChatManager.chatOfficeIds.
  static const Set<String> _adminUids = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    'SdPI69ChOvepuq9HrlW6no9rMRn1', // Admin
  };

  // Global navigator key for notification tap navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  /// Bildirime basınca açılacak sayfa ancak ana sayfa açıkken ve güncelleme
  /// ekranı engellemiyorken açılır; o zamana kadar bekletilir (bkz.
  /// [NotificationTapGate]).
  late final NotificationTapGate _tapGate =
      NotificationTapGate(onOpen: _handleNotificationTap);

  // Overlay entry for in-app notification banner
  OverlayEntry? _currentBanner;

  /// Açık sohbet sayfaları; en üstteki (görünen) en sonda. Sohbet üstüne
  /// sohbet açılabilir (bir sohbetteyken başka bir danışanın bildirimine
  /// basılınca, en fazla [OpenChats.maxStackedChats]); üstteki kapanınca
  /// alttakinin bildirim bastırması geri gelir.
  final OpenChats _openChats = OpenChats();

  /// Uygulama ön planda mı. Arka plandayken hiçbir sohbetin bildirimi
  /// bastırılmaz.
  bool _inForeground = true;

  /// Initialize FCM service
  /// 
  /// Call this in main() after Firebase.initializeApp()
  /// Returns false if FCM is not supported on this platform.
  Future<bool> initFcmService({required GlobalKey<NavigatorState> navigatorKey}) async {
    if (!isSupported) {
      return false;
    }

    _navigatorKey = navigatorKey;

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

    // Set up message handlers
    _setupMessageHandlers();

    // Jeton burada beklenmez: açılış (runApp) ona takılmasın. Firestore
    // yazımı ancak sunucu onaylayınca biter; çevrimdışı açılışta hiç bitmez
    // ve uygulama açılış ekranında kalırdı. Kaydı aşağıdaki oturum dinleyicisi
    // yapar (ilk olayı açıktaki oturumdur); yazım bağlantı gelince gider.

    // Clear any existing badge count when app starts
    await clearBadge();

    // Handle app launch from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _tapGate.open(initialMessage.data);
    }

    // Listen to auth state changes to save token when user logs in
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        saveFcmToken();
      } else {
        // Oturum kapandı: bekleyen bildirim açılmaz.
        _tapGate.clearPending();
      }
    });

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
      final isSupported = await AppBadgePlus.isSupported();
      if (!isSupported) {
        return;
      }

      // A count of 0 clears the badge.
      await AppBadgePlus.updateBadge(0);
    } catch (e) {
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      await _messaging.requestPermission( //BUNU HER ACTIGBIMDA ISTICEK MI???
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
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
    // Check if user is logged in
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      // User is logged out - check if we should show this notification type
      final type = (message.data['type'] ?? '').toString();
      final isChatNotification = type == 'chat' || type == 'chat_admin';
      final isAnnouncementNotification = type == 'news';
      
      if (isChatNotification && !allowChatNotificationsWhenLoggedOut) {
        return;
      }
      if (isAnnouncementNotification && !allowAnnouncementNotificationsWhenLoggedOut) {
        return;
      }
      // For other notification types when logged out, still skip
      if (!isChatNotification && !isAnnouncementNotification) {
        return;
      }
    } else if (!isMeantFor(message.data, currentUser.uid)) {
      return;
    }

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    // Check if we should suppress this notification (user is already viewing this chat)
    if (_shouldSuppressNotification(message.data)) {
      return;
    }

    // Check in-app notification flags based on notification type
    final type = (message.data['type'] ?? '').toString();
    final isChatNotification = type == 'chat' || type == 'chat_admin';
    final isAnnouncementNotification = type == 'news';
    
    if (isChatNotification && !showInAppChatNotifications) {
      return;
    }
    if (isAnnouncementNotification && !showInAppAnnouncementNotifications) {
      return;
    }

    _showInAppNotification(
      context: context,
      title: notification.title ?? NotificationConstants.inAppNotificationDefaultTitle,
      body: notification.body ?? '',
      data: message.data,
    );
  }

  /// Bildirim [uid] kullanıcısına mı gönderilmiş. Cihazın jetonu, önceki
  /// hesabın kaydından sunucu onu silene kadar orada da durabilir (bkz.
  /// [removeFcmToken]); o hesabın sohbet bildirimleri bu cihazda oturumu açık
  /// kişiye gösterilmez. Danışanın sohbet bildirimi kendi sohbetinindir
  /// (`chatId` = UID), `chat_admin` yalnızca ofise gider
  /// ([ChatManager.chatOfficeIds]).
  @visibleForTesting
  static bool isMeantFor(Map<String, dynamic> data, String uid) {
    final String type = (data['type'] ?? '').toString();
    final bool isChatOffice = ChatManager.isChatOfficeUid(uid);
    switch (type) {
      case 'chat':
        return !isChatOffice && (data['chatId'] ?? '').toString() == uid;
      case 'chat_admin':
        return isChatOffice;
      default:
        return true;
    }
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
      return true;
    }

    // Check if user is currently viewing this chat
    final notificationChatId = (data['chatId'] ?? '').toString();
    if (notificationChatId.isEmpty) {
      return false;
    }

    // Suppress if the notification is for the chat the user is currently viewing
    return activeChatId == notificationChatId;
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
          _tapGate.open(data);
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
    // Check if user is logged in before processing notification tap
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      final type = (message.data['type'] ?? '').toString();
      final isChatNotification = type == 'chat' || type == 'chat_admin';
      final isAnnouncementNotification = type == 'news';
      
      if (isChatNotification && !allowChatNotificationsWhenLoggedOut) {
        clearBadge();
        return;
      }
      if (isAnnouncementNotification && !allowAnnouncementNotificationsWhenLoggedOut) {
        clearBadge();
        return;
      }
    }
    
    _tapGate.open(message.data);
    
    // Clear badge when user taps a notification
    clearBadge();
  }

  /// Handle notification tap navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    final user = _auth.currentUser;

    if (navigator == null || user == null) return;

    final type = (data['type'] ?? '').toString();
    final isChatOffice = ChatManager.isChatOfficeUid(user.uid);

    // İfade bildirimleri tepkinin bırakıldığı mesajı taşır: sohbet o mesajda
    // açılır (bkz. ChatPage.focusMessageId).
    final messageIdValue = (data['messageId'] ?? '').toString();
    final String? focusMessageId =
        messageIdValue.isEmpty ? null : messageIdValue;

    switch (type) {
      case 'chat':
        // Admin -> User notification
        if (isChatOffice) {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isNotEmpty) {
            _openAdminChat(navigator, chatId, focusMessageId);
          } else {
            navigator.push(AdminChatListPage.route());
          }
        } else {
          _openClientChat(navigator, user.uid, focusMessageId);
        }
        break;

      case 'chat_admin':
        // User -> Admin notification
        if (!isChatOffice) return;

        final chatId = (data['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          _openAdminChat(navigator, chatId, focusMessageId);
        } else {
          navigator.push(AdminChatListPage.route());
        }
        break;

      case 'news':
        // News/announcement notification - navigate to news list
        // User can then tap on the specific news to see details
        navigator.push(MaterialPageRoute(
          builder: (_) => const NewsListPage(),
        ));
        break;
    }
  }

  /// Admin'e bildirimdeki sohbeti açar: yeni sohbet açık sohbetin üstüne
  /// açılır, üst üste en fazla iki sohbet kalır (bkz.
  /// [OpenChats.showAdminChat]).
  void _openAdminChat(
    NavigatorState navigator,
    String chatId,
    String? focusMessageId,
  ) {
    _openChats.showAdminChat(
      navigator,
      chatId,
      focusMessageId,
      () => ChatPage.route(
        overrideChatId: chatId,
        focusMessageId: focusMessageId,
      ),
    );
  }

  /// Danışana kendi sohbetini açar; sohbet zaten açıksa ikinci bir sohbet
  /// sayfası açılmaz (bkz. [OpenChats.showClientChat]).
  void _openClientChat(
    NavigatorState navigator,
    String chatId,
    String? focusMessageId,
  ) {
    _openChats.showClientChat(
      navigator,
      chatId,
      focusMessageId,
      () => ChatPage.route(focusMessageId: focusMessageId),
    );
  }

  /// Ana sayfa ([page]) açıldı; ilk karesinden sonra çağrılır. Bekleyen
  /// bildirim varsa şimdi açılır.
  void markHomeReady(Object page) => _tapGate.homeShown(page);

  /// Ana sayfa ([page]) kapandı.
  void markHomeGone(Object page) => _tapGate.homeGone(page);

  /// Güncelleme ekranı uygulamayı engelliyor mu (bkz. `AppUpdateGate`);
  /// engel kalkınca bekleyen bildirim açılır.
  void setUpdateBlocking(bool blocking) =>
      _tapGate.setUpdateBlocking(blocking);

  /// Save FCM token to Firestore for current user.
  /// Uses a single token per user (overwrites previous token).
  /// Kayıttaki jeton zaten bu cihazınkiyse yazılmaz.
  Future<void> saveFcmToken() async {
    if (!isSupported) return;
    
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      _listenForTokenRefresh();

      final token = await _messaging.getToken();
      if (token == null) {
        return;
      }

      await _saveTokenIfChanged(user.uid, token);
    } catch (e) {
    }
  }

  /// [token]'ı kullanıcının kaydına yazar; sunucudaki kayıtta zaten o varsa
  /// ya da hesap silme talebi varsa (giriş o hesabı hemen çıkarır, bkz.
  /// `LoginProvider.login`) yazmaz. Kayıt sunucudan okunamazsa (çevrimdışı)
  /// karşılaştırma yapılmaz, jeton yine yazılır: yazma bağlantı gelince gider.
  /// Cihazdaki eski bir kopyayla karşılaştırılsaydı, kayıt bu arada başka bir
  /// cihazınkine dönmüşken yazma atlanabilirdi.
  Future<void> _saveTokenIfChanged(String uid, String token) async {
    final userDoc = _firestore.collection('users').doc(uid);
    try {
      final snapshot =
          await userDoc.get(const GetOptions(source: Source.server));
      final Map<String, dynamic>? data = snapshot.data();
      if (data?['fcmToken'] == token) return;
      if (data?['isUserRequestedRemoval'] == true) return;
    } catch (e) {
      // Sunucuya ulaşılamadı: koşulsuz yazılır.
    }

    // update (set-merge değil): kullanıcı kaydı cihazda yokken çevrimdışı
    // yazım cihazda yalnızca jetonlu bir kayıt oluşturmasın; KVKK kontrolü
    // onu "onay yok" sanardı (bkz. UserProvider.checkKvkkConsent). Kaydı
    // admin açar, sunucuda hep vardır.
    await userDoc.update({'fcmToken': token});
  }

  /// Keeps the stored token in sync when FCM rotates it. Idempotent: only the
  /// first call subscribes.
  void _listenForTokenRefresh() {
    if (!isSupported || _tokenRefreshSub != null) return;

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      try {
        await _saveTokenIfChanged(currentUser.uid, newToken);
      } catch (e) {
      }
    });
  }

  /// Remove FCM token from Firestore for current user.
  /// Call this on logout to stop receiving notifications on this device.
  /// Kayıttaki jeton bu cihazın değilse (kullanıcı sonra başka bir cihazdan
  /// girdi) silinmez: bu cihazdan çıkmak o cihazın bildirimlerini kesmez. Bu
  /// cihazın jetonu yoksa kayda dokunulmaz (kayıttaki başka bir cihazınkidir).
  /// Kayıt okunamazsa (ör. çevrimdışı) jeton koşulsuz silinmeye çalışılır ama
  /// bu silme sunucuya hemen gitmez: Firestore onu çıkan kullanıcının yazma
  /// sırasında tutar ve ancak o kullanıcı bu cihazda yeniden girince gönderir.
  /// O zamana kadar bu kullanıcının bildirimleri bu cihaza gelmeye devam eder.
  /// Cihazda başka bir hesap girince jeton onun kaydına yazılır ve sunucu
  /// (`releaseFcmTokenFromOtherUsers`) jetonu önceki hesabın kaydından siler;
  /// uygulama açıkken başkasına ait sohbet bildirimi zaten gösterilmez (bkz.
  /// [isMeantFor]). Çıkış bu yazmayı en fazla [_logoutWriteTimeout] bekler;
  /// çevrimdışıyken donmaz.
  Future<void> removeFcmToken() async {
    if (!isSupported) return;
    
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    final String? token;
    try {
      // Çevrimdışıyken jeton okuması da uzun sürebilir: çıkışı bekletmesin.
      token = await _messaging.getToken().timeout(_logoutWriteTimeout);
    } catch (e) {
      return;
    }
    if (token == null) return;

    final userDoc = _firestore.collection('users').doc(user.uid);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDoc);
        if (snapshot.data()?['fcmToken'] != token) return;
        transaction.update(userDoc, {'fcmToken': FieldValue.delete()});
      }).timeout(_logoutWriteTimeout);
      return;
    } catch (e) {
      // Kayıt okunamadı: aşağıda koşulsuz silinir.
    }
    try {
      await userDoc.set({
        'fcmToken': FieldValue.delete(),
      }, SetOptions(merge: true)).timeout(_logoutWriteTimeout);
    } catch (e) {
    }
  }

  /// Çıkışta jeton silme yazımının en fazla bekleneceği süre.
  static const Duration _logoutWriteTimeout = Duration(seconds: 5);

  /// Check if a user is an admin
  static bool isAdmin(String uid) => _adminUids.contains(uid);

  /// Bir sohbet sayfası açıldı: o sohbetin uygulama içi bildirimleri, sayfa
  /// en üstte kaldıkça bastırılır. [route] sayfanın rotası,
  /// [onNotificationOpen] sohbet açıkken bu sohbetin bildirimine basılınca
  /// bildirimin mesaj kimliğiyle (yoksa null) çağrılır (bkz. [OpenChats]).
  void openChat(
    String chatId, {
    Route<dynamic>? route,
    ValueChanged<String?>? onNotificationOpen,
  }) {
    _openChats.open(
      chatId,
      route: route,
      onNotificationOpen: onNotificationOpen,
    );
  }

  /// Sohbet sayfası kapandı. Yalnızca o sayfanın kaydı düşer (sayfanın
  /// [openChat]'e verdiği işlevle bulunur); altta açık başka bir sohbet
  /// varsa onun bastırması sürer.
  void closeChat(String chatId, {ValueChanged<String?>? onNotificationOpen}) {
    _openChats.close(chatId, onNotificationOpen: onNotificationOpen);
  }

  /// Uygulama ön plana geldi / arka plana gitti.
  void setInForeground(bool inForeground) {
    _inForeground = inForeground;
  }

  /// Bildirimleri bastırılan (ekranda görünen) sohbet; yoksa null.
  String? get activeChatId =>
      _inForeground ? _openChats.topChatId : null;
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
                      color: Colors.black.withValues(alpha: 0.25),
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
                      color: Colors.white.withValues(alpha: 0.15),
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
                          color: Colors.white.withValues(alpha: 0.15),
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

