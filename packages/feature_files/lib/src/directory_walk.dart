import 'package:adb_core/adb_core.dart';

/// One file found while walking a tree, with its path relative to the root.
class WalkedFile {
  const WalkedFile(this.entry, this.relativePath);

  final AdbFileEntry entry;

  /// Path relative to the walk root, e.g. `Camera/IMG_0001.jpg`.
  final String relativePath;
}

/// The result of walking a remote directory tree.
class DirectoryWalk {
  DirectoryWalk({
    required this.root,
    required this.files,
    required this.directories,
    required this.skipped,
    required this.unsupported,
    required this.truncated,
  });

  final String root;
  final List<WalkedFile> files;

  /// Relative paths of every directory, so they can be recreated in order.
  final List<String> directories;

  /// Directories that could not be read. Surfaced rather than silently
  /// dropped, so a partial copy is never mistaken for a complete one.
  final List<String> skipped;

  /// Entries that exist but cannot be transferred: symlinks, sockets, fifos,
  /// device nodes, and anything the device would not stat.
  ///
  /// Note that `LIS2` reports a symlink with mode 0 (type unknown) rather than
  /// `S_IFLNK` — verified on a Galaxy A71 — so links usually land here rather
  /// than being positively identified. Either way they are never followed,
  /// which is what stops `/sdcard`-style link cycles from looping forever.
  final List<String> unsupported;

  /// True when a limit was hit and the walk is incomplete.
  final bool truncated;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.entry.size);
  int get fileCount => files.length;
  bool get isComplete => !truncated && skipped.isEmpty;
}

/// Limits that stop a walk from running away.
///
/// A device tree can be enormous (`/` includes `/proc`), and symlinks can form
/// cycles — `/sdcard` is itself a symlink to `/storage/emulated/0`. Both are
/// normal on Android, so a recursive copy needs hard stops rather than trust.
class WalkLimits {
  const WalkLimits({
    this.maxFiles = 20000,
    this.maxDepth = 32,
    this.maxBytes = 32 * 1024 * 1024 * 1024,
  });

  final int maxFiles;
  final int maxDepth;
  final int maxBytes;

  static const unlimited = WalkLimits(
    maxFiles: 1 << 30,
    maxDepth: 1024,
    maxBytes: 1 << 50,
  );
}
