import UIKit
import Flutter
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let platformInfoChannel = FlutterMethodChannel(
      name: "ngy_app/platform_info",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    platformInfoChannel.setMethodCallHandler { call, result in
      if call.method == "isIosAppOnMac" {
        result(ProcessInfo.processInfo.isiOSAppOnMac)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
