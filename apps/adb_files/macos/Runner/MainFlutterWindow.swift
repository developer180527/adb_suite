import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let args = Array(CommandLine.arguments.dropFirst())

    // Flutter on macOS does NOT forward process arguments to Dart's main() by
    // default -- `main(List<String> args)` receives an empty list unless the
    // runner passes them through here. A detached tab carries its directory in
    // argv, so without this the new window always opens at the default path.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = args

    let flutterViewController = FlutterViewController(project: project)
    self.contentViewController = flutterViewController

    // Flutter's default window is too small for a file manager: the sidebar
    // plus four columns need real width, and a short window shows only a
    // handful of rows.
    self.contentMinSize = NSSize(width: 820, height: 480)

    let width = Self.flagValue(args, "--width=")
    let height = Self.flagValue(args, "--height=")

    if let width = width, let height = height {
      // A window torn off from a tab must match the window it came from.
      // macOS restores a saved frame *after* awakeFromNib, which would undo
      // this, so restoration is switched off for detached windows only --
      // ordinary launches still remember the size the user chose.
      self.isRestorable = false
      self.setContentSize(NSSize(width: width, height: height))

      if let x = Self.flagValue(args, "--x="), let y = Self.flagValue(args, "--y=") {
        // AppKit's origin is bottom-left, which is what setFrameOrigin wants.
        self.setFrameOrigin(NSPoint(x: x, y: y))
      } else {
        // Cascade slightly so the new window does not land exactly on top of
        // the one it was torn from.
        self.setFrameOrigin(NSPoint(x: frame.origin.x + 28, y: frame.origin.y - 28))
      }
    } else {
      self.setContentSize(NSSize(width: 1180, height: 760))
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private static func flagValue(_ args: [String], _ prefix: String) -> Double? {
    guard let match = args.first(where: { $0.hasPrefix(prefix) }) else {
      return nil
    }
    return Double(match.dropFirst(prefix.count))
  }
}
