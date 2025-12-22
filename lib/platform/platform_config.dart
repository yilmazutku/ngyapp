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

