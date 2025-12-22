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

