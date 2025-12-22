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

