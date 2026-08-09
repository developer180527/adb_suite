/// Getting from "an app just launched" to "a device is ready".
///
/// Device discovery, the authorisation dance, wireless pairing and the TLS
/// upgrade are the same problem in every app built on this stack, and they are
/// the part where a subtle mistake is a security bug rather than a bug. One
/// copy, shared.
///
/// This package deliberately stops at [AdbSession]. It does not know what a
/// file is, or a log line — each app builds its own services on top of the
/// session, which is what keeps a debugger app from dragging in file transfer
/// and a file manager from dragging in logcat.
library;

export 'src/connect_panel.dart';
export 'src/connection_controller.dart';
export 'src/wireless_reply.dart';
