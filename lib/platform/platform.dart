/// Platform-specific configuration exports.
/// 
/// This module provides a Strategy Pattern implementation for handling
/// platform-specific initialization, particularly for push notifications.
/// 
/// Usage in main.dart:
/// ```dart
/// import 'platform/platform_config_factory.dart';
/// 
/// void main() async {
///   // ...
///   platformConfig = await PlatformConfigFactory.initializePlatform(
///     navigatorKey: navKey,
///   );
/// }
/// ```

export 'platform_config.dart';
export 'platform_config_android.dart';
export 'platform_config_factory.dart';
export 'platform_config_ios.dart';

