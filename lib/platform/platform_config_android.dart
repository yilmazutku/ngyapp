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

