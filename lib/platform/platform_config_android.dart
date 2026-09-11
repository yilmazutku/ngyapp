import 'package:flutter/widgets.dart';

import '../services/fcm_service.dart';
import 'platform_config.dart';

/// Android-specific platform configuration.
/// 
/// Handles:
/// - FCM push notifications (via FcmService)
/// - Notification channels are created in native code (MyApplication.kt)
class AndroidPlatformConfig implements PlatformConfig {
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

    // Configure notifications
    await configurePushNotifications();
    await configureLocalNotifications();
  }

  @override
  Future<void> configurePushNotifications() async {
    // Initialize FCM service
    // Notification channels are created in native Android code (MyApplication.kt)
    // Channel ID: chat_messages_v2 with IMPORTANCE_HIGH
    await FcmService().initFcmService(navigatorKey: _navigatorKey!);
  }

  @override
  Future<void> configureLocalNotifications() async {
    // Local notifications are handled by NotificationService
    // Channel configuration is done in native code
  }

  @override
  Future<void> dispose() async {
  }
}

