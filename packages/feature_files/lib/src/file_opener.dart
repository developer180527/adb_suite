import 'dart:async';
import 'dart:io';

import 'package:adb_core/adb_core.dart';

import 'file_service.dart';
import 'remote_path.dart';

/// Downloads device files to a local cache and hands them to the desktop.
///
/// Opening a remote file has no meaning on its own — the OS can only open
/// something on local disk. So "open" means: fetch to a cache directory, then
/// hand the path to the platform's default-application launcher.
///
/// The cache is keyed on the remote path and revalidated against size and
/// mtime, so reopening an unchanged file is instant and a changed one is
/// re-fetched.
class FileOpener {
  FileOpener(this._service, {required this.cacheDirectory});

  final FileService _service;

  /// Root for cached downloads. Callers should pick a real cache location
  /// (`~/Library/Caches/<app>` on macOS) so the OS can reclaim it.
  final Directory cacheDirectory;

  /// Local path a given remote file caches to.
  ///
  /// Remote paths are namespaced by a hash so two files with the same name in
  /// different directories cannot collide, while the basename is preserved so
  /// the opened window has a sensible title and the right extension.
  File cachePathFor(String remotePath) {
    final normalized = RemotePath.normalize(remotePath);
    final bucket = _hash(RemotePath.parent(normalized));
    return File(
      '${cacheDirectory.path}/$bucket/${RemotePath.basename(normalized)}',
    );
  }

  /// True when the cached copy still matches the device.
  ///
  /// Compares size and mtime rather than hashing: hashing would mean pulling
  /// the whole file, which defeats the point of the cache.
  bool isFresh(AdbFileEntry entry) {
    final cached = cachePathFor(entry.path);
    if (!cached.existsSync()) return false;

    final stat = cached.statSync();
    if (stat.size != entry.size) return false;

    final remoteModified = entry.modified;
    if (remoteModified == null) return false;

    // Second precision on the device side, so allow a second of slack.
    return !stat.modified.isBefore(
      remoteModified.subtract(const Duration(seconds: 1)),
    );
  }

  /// Ensures a current local copy exists and returns it.
  Future<File> ensureLocal(
    AdbFileEntry entry, {
    void Function(TransferProgress)? onProgress,
    bool force = false,
  }) async {
    final cached = cachePathFor(entry.path);

    if (!force && isFresh(entry)) {
      onProgress?.call(TransferProgress(entry.size, entry.size));
      return cached;
    }

    cached.parent.createSync(recursive: true);
    await _service.pull(entry.path, cached.path, onProgress: onProgress);

    // Stamp the local copy with the device's mtime so freshness checks work
    // on the next open.
    final remoteModified = entry.modified;
    if (remoteModified != null) {
      try {
        cached.setLastModifiedSync(remoteModified);
      } on FileSystemException {
        // Not fatal -- we just re-download next time.
      }
    }

    return cached;
  }

  /// Downloads if needed, then opens with the platform's default application.
  Future<File> openInDefaultApp(
    AdbFileEntry entry, {
    void Function(TransferProgress)? onProgress,
  }) async {
    if (entry.isDirectory) {
      throw ArgumentError('Cannot open a directory in an application');
    }

    final file = await ensureLocal(entry, onProgress: onProgress);
    await openLocal(file.path);
    return file;
  }

  /// Hands an existing local path to the OS.
  static Future<void> openLocal(String path) async {
    final (command, args) = _openCommand(path);
    final result = await Process.run(command, args);
    if (result.exitCode != 0) {
      throw AdbFailure(
        'Could not open "$path": ${result.stderr.toString().trim()}',
      );
    }
  }

  /// Shows the file selected in the platform file manager.
  static Future<void> revealLocal(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else {
      // No universal "reveal" on Linux; opening the parent is the closest.
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  static (String, List<String>) _openCommand(String path) {
    if (Platform.isMacOS) return ('open', [path]);
    if (Platform.isWindows) {
      // `start` is a cmd builtin, and its first quoted argument is the window
      // title -- hence the empty string before the path.
      return ('cmd', ['/c', 'start', '', path]);
    }
    return ('xdg-open', [path]);
  }

  /// Total bytes currently cached.
  Future<int> cacheSize() async {
    if (!cacheDirectory.existsSync()) return 0;
    var total = 0;
    await for (final entity in cacheDirectory.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clearCache() async {
    if (cacheDirectory.existsSync()) {
      await cacheDirectory.delete(recursive: true);
    }
  }

  /// FNV-1a, purely to namespace cache directories. Not security relevant.
  static String _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
