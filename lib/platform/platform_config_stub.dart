import 'package:flutter/widgets.dart';

import '../services/fcm_service.dart';
import 'platform_config.dart';

/// Stub implementation for platforms without push notification support.
/// 
/// Used for:
/// - Web (limited FCM support, handled differently)
/// - Windows (no FCM support)
/// - Linux (no FCM support)
class StubPlatformConfig implements PlatformConfig {
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
    FcmService().setNavigatorKey(navigatorKey);
  }

  @override
  Future<void> configurePushNotifications() async {
  }

  @override
  Future<void> configureLocalNotifications() async {
  }

  @override
  Future<void> dispose() async {
  }
}

