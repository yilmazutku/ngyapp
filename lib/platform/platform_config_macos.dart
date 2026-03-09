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

