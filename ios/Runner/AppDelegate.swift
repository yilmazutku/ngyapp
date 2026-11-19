import UIKit
import Flutter
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "PlatformInfo") {
      let platformInfoChannel = FlutterMethodChannel(
        name: "ngy_app/platform_info",
        binaryMessenger: registrar.messenger()
      )
      platformInfoChannel.setMethodCallHandler { call, result in
        if call.method == "isIosAppOnMac" {
          result(ProcessInfo.processInfo.isiOSAppOnMac)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
