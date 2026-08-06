import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Flutter's default window is too small for a file manager: the sidebar
    // plus four columns need real width, and a short window shows only a
    // handful of rows. Open at a comfortable desktop size, centred.
    let defaultSize = NSSize(width: 1180, height: 760)
    self.setContentSize(defaultSize)

    // Below this the columns start colliding with the sidebar.
    self.contentMinSize = NSSize(width: 820, height: 480)

    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
