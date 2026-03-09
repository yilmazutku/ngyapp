import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import 'platform_config.dart';
import 'platform_config_android.dart';
import 'platform_config_ios.dart';
import 'platform_config_macos.dart';
import 'platform_config_stub.dart';

class PlatformConfigFactory {
  static final Logger _logger = Logger.forClass(PlatformConfigFactory);

  static PlatformConfig create() {
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
      _logger.info('Creating Windows platform config (no push notifications)');
      return StubPlatformConfig(platformName: 'Windows');
    }

    _logger.warn('Unknown platform, using stub config');
    return StubPlatformConfig(platformName: 'Unknown');
  }

  static Future<PlatformConfig> initializePlatform({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    final config = create();
    await config.initialize(navigatorKey: navigatorKey);
    return config;
  }
}
