import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'ios_app_on_mac.dart';

class HealthStepsService {
  HealthStepsService({Health? health}) : _injectedHealth = health;

  static final HealthStepsService shared = HealthStepsService();

  static const List<HealthDataType> _types = <HealthDataType>[
    HealthDataType.STEPS,
  ];

  final Health? _injectedHealth;
  late final Health _health = _injectedHealth ?? Health();
  bool _granted = false;
  bool _asked = false;
  Future<bool>? _pendingAccess;

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
      if (!await _ensureAccess()) return null;
      return await _health.getTotalStepsInInterval(
        DateTime(day.year, day.month, day.day),
        DateTime(day.year, day.month, day.day + 1),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensureAccess() {
    if (_granted) return Future<bool>.value(true);
    return _pendingAccess ??=
        _checkAccess().whenComplete(() => _pendingAccess = null);
  }

  Future<bool> _checkAccess() async {
    try {
      if (!await _health.isHealthConnectAvailable()) return false;
      if (await _health.hasPermissions(_types) == true) {
        return _granted = true;
      }
      if (_asked) return false;
      _asked = true;
      return _granted = await _health.requestAuthorization(_types);
    } catch (_) {
      return false;
    }
  }
}
