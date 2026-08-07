import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Kept alive for the window's lifetime; the channel stops working if this
  /// is released.
  private var contextMenuChannel: FlutterMethodChannel?
  private var contextMenu: NativeContextMenu?

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

    // A real AppKit context menu. Flutter's showMenu is a Material popup that
    // never quite matches the system -- wrong metrics, no vibrancy, no
    // keyboard behaviour. This hands the items to NSMenu instead.
    let channel = FlutterMethodChannel(
      name: "adb_files/context_menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let menu = NativeContextMenu(view: flutterViewController.view)
    channel.setMethodCallHandler { call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      menu.show(arguments: call.arguments, result: result)
    }
    self.contextMenuChannel = channel
    self.contextMenu = menu

    super.awakeFromNib()
  }

  private static func flagValue(_ args: [String], _ prefix: String) -> Double? {
    guard let match = args.first(where: { $0.hasPrefix(prefix) }) else {
      return nil
    }
    return Double(match.dropFirst(prefix.count))
  }
}

/// Builds and pops up an NSMenu on behalf of Dart.
///
/// Items arrive as `{id, label, enabled}` maps, with a null entry meaning a
/// separator. The reply is the chosen item's id, or nil if the user dismissed
/// the menu.
class NativeContextMenu: NSObject {
  private let view: NSView
  private var pending: FlutterResult?

  init(view: NSView) {
    self.view = view
    super.init()
  }

  func show(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let rawItems = args["items"] as? [[String: Any]?],
      let x = args["x"] as? Double,
      let y = args["y"] as? Double
    else {
      result(FlutterError(code: "bad_args",
                          message: "Expected items, x and y",
                          details: nil))
      return
    }

    let menu = NSMenu()
    menu.autoenablesItems = false

    for raw in rawItems {
      guard let raw = raw else {
        menu.addItem(.separator())
        continue
      }
      let item = NSMenuItem(
        title: raw["label"] as? String ?? "",
        action: #selector(itemSelected(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.isEnabled = raw["enabled"] as? Bool ?? true
      item.representedObject = raw["id"]
      menu.addItem(item)
    }

    pending = result

    // Flutter reports the pointer in logical points from the view's top-left;
    // AppKit's origin is bottom-left, hence the flip.
    let point = NSPoint(x: x, y: view.bounds.height - y)
    let shown = menu.popUp(positioning: nil, at: point, in: view)

    // popUp is modal and returns once dismissed. If nothing was chosen the
    // action never fired, so settle the reply here -- otherwise the Dart side
    // waits forever.
    if !shown || pending != nil {
      let reply = pending
      pending = nil
      reply?(nil)
    }
  }

  @objc private func itemSelected(_ sender: NSMenuItem) {
    let reply = pending
    pending = nil
    reply?(sender.representedObject)
  }
}
