import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../models/logger.dart';
import 'platform_config.dart';
import 'platform_config_android.dart';
import 'platform_config_ios.dart';

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

    throw UnsupportedError('Platform not supported: only Android and iOS are supported');
  }

  static Future<PlatformConfig> initializePlatform({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    final config = create();
    await config.initialize(navigatorKey: navigatorKey);
    return config;
  }
}
