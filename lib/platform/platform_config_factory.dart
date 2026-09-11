import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import 'platform_config.dart';
import 'platform_config_android.dart';
import 'platform_config_ios.dart';
import 'platform_config_macos.dart';
import 'platform_config_stub.dart';

class PlatformConfigFactory {
  static PlatformConfig create() {
    if (Platform.isAndroid) {
      return AndroidPlatformConfig();
    }

    if (Platform.isIOS) {
      return IosPlatformConfig();
    }

    if (Platform.isMacOS) {
      return MacosPlatformConfig();
    }

    if (Platform.isWindows) {
      return StubPlatformConfig(platformName: 'Windows');
    }

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
