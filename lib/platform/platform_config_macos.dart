import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

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

    // Configure notifications
    await configurePushNotifications();
    await configureLocalNotifications();
  }

  @override
  Future<void> configurePushNotifications() async {
    // Set foreground notification presentation options
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, // Show alert banner in Notification Center
      badge: true, // Update dock badge
      sound: true, // Play sound
    );

    // Request notification permissions
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    // Get APNs token (macOS also uses APNs like iOS)
    try {
      await _messaging.getAPNSToken();
    } catch (e) {
    }

    // Initialize FCM service
    await FcmService().initFcmService(navigatorKey: _navigatorKey!);
  }

  @override
  Future<void> configureLocalNotifications() async {
    // Local notifications are handled by NotificationService
  }

  @override
  Future<void> dispose() async {
  }
}

