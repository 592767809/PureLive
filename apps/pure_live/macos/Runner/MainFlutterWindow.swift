import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMethodChannel(
      name: "pure_live/secret_cipher", binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler(SecretCipher.shared.handle)

    super.awakeFromNib()
  }

  // Stays hidden until the desktop shell has given it its size and place
  // (window_manager's waitUntilReadyToShow).
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
