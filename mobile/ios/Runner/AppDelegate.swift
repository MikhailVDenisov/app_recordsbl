import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RecordsblDisk") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "recordsbl/disk",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "freeBytes" {
        do {
          let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
          if let n = attrs[.systemFreeSize] as? NSNumber {
            result(n.int64Value)
          } else {
            result(nil)
          }
        } catch {
          result(nil)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
