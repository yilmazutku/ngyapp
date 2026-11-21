import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'ios_app_on_mac.dart';

class HealthStepsService {
  const HealthStepsService();

  static const List<HealthDataType> _types = <HealthDataType>[
    HealthDataType.STEPS,
  ];

  static Health? _health;
  static Future<bool>? _access;

  static bool supportedOn(TargetPlatform platform, {required bool iosAppOnMac}) {
    switch (platform) {
      case TargetPlatform.android:
        return true;
      case TargetPlatform.iOS:
        return !iosAppOnMac;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  bool get isSupported =>
      !kIsWeb &&
      supportedOn(defaultTargetPlatform, iosAppOnMac: isIosAppOnMac);

  Future<int?> stepsForDay(DateTime day) async {
    if (!isSupported) return null;
    try {
      if (!await (_access ??= _requestAccess())) return null;
      return await _health!.getTotalStepsInInterval(
        DateTime(day.year, day.month, day.day),
        DateTime(day.year, day.month, day.day + 1),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _requestAccess() async {
    try {
      final Health health = _health ??= Health();
      await health.configure();
      if (!await health.isHealthConnectAvailable()) return false;
      if (await health.hasPermissions(_types) == true) return true;
      return await health.requestAuthorization(_types);
    } catch (_) {
      return false;
    }
  }
}
