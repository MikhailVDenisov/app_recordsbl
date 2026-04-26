import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "recordsbl/disk",
        binaryMessenger: controller.engine.binaryMessenger
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

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
