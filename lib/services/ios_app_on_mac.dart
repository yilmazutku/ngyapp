import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _platformInfoChannel =
    MethodChannel('ngy_app/platform_info');

bool _isIosAppOnMac = false;

bool get isIosAppOnMac => _isIosAppOnMac;

Future<void> loadIosAppOnMac() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    _isIosAppOnMac = false;
    return;
  }
  try {
    _isIosAppOnMac =
        await _platformInfoChannel.invokeMethod<bool>('isIosAppOnMac') ??
            false;
  } catch (_) {
    _isIosAppOnMac = false;
  }
}
