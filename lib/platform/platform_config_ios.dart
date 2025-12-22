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

