import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    MultiCameraPlugin.register(with: controller.registrar(forPlugin: "MultiCameraPlugin"))
    WebcamPlugin.register(with: controller.registrar(forPlugin: "WebcamPlugin"))
    super.applicationDidFinishLaunching(notification)
  }
}
