import 'package:adb_core/adb_core.dart';

import 'directory_walk.dart';
import 'models/directory_listing.dart';
import 'posix_shell.dart';
import 'remote_path.dart';

/// Browsing and file management on a device.
///
/// Listing, stat, and transfer use the sync protocol, which returns structured
/// metadata. Delete, mkdir, rename, and copy have no sync equivalent and go
/// through the shell — every path is quoted by [PosixShell].
class FileService {
  FileService(this._session);

  final AdbSession _session;

  /// Lists [path], distinguishing empty from unreadable.
  ///
  /// `LIST` returns an empty result for a directory the shell user cannot
  /// read, so an empty listing triggers one extra shell probe to find out
  /// which it actually was. The probe only runs in that case, so the common
  /// path stays a single sync round trip.
  Future<DirectoryListing> list(String path) async {
    final normalized = RemotePath.normalize(path);

    List<AdbFileEntry> entries;
    try {
      entries = await _session.sync.list(normalized);
    } on AdbException catch (e) {
      return DirectoryFailed(normalized, e);
    }

    if (entries.isNotEmpty) {
      // The sync protocol really does return `.` and `..` (verified against a
      // Galaxy A71). This filter is load-bearing, not defensive: without it
      // any recursive walk follows `.` and never terminates.
      return DirectoryContents(
        normalized,
        entries.where((e) => e.name != '.' && e.name != '..').toList(),
      );
    }

    return _diagnoseEmpty(normalized);
  }

  /// Works out why a listing came back empty.
  Future<DirectoryListing> _diagnoseEmpty(String path) async {
    final quoted = PosixShell.quote(path);
    final result = await _session.shell.run(
      'if [ ! -e $quoted ]; then echo MISSING; '
      'elif [ ! -d $quoted ]; then echo NOTDIR; '
      'elif [ ! -r $quoted ]; then echo DENIED; '
      'else echo EMPTY; fi',
    );

    return switch (result.trimmed) {
      'MISSING' => DirectoryMissing(path),
      'NOTDIR' => DirectoryNotADirectory(path),
      'DENIED' => DirectoryDenied(path),
      'EMPTY' => DirectoryContents(path, const []),
      // An unrecognised answer means the probe itself failed; treat the
      // listing as genuinely empty rather than inventing a cause.
      _ => DirectoryContents(path, const []),
    };
  }

  Future<AdbFileEntry> stat(String path) =>
      _session.sync.stat(RemotePath.normalize(path));

  /// Walks a directory tree breadth-first, collecting every file beneath it.
  ///
  /// **Symlinks are never followed.** `/sdcard` is a symlink to
  /// `/storage/emulated/0` on essentially every Android device, and following
  /// links would walk the same tree twice or loop forever. Anything that is
  /// not a regular file or a readable directory is recorded in
  /// [DirectoryWalk.unsupported] rather than dropped silently.
  ///
  /// Unreadable subdirectories are recorded in [DirectoryWalk.skipped] rather
  /// than aborting — one locked folder should not fail a whole copy, but the
  /// result must not look complete either.
  Future<DirectoryWalk> walkDirectory(
    String path, {
    WalkLimits limits = const WalkLimits(),
    void Function(int filesFound, int bytesFound)? onProgress,
  }) async {
    final root = RemotePath.normalize(path);
    final files = <WalkedFile>[];
    final directories = <String>[];
    final skipped = <String>[];
    final unsupported = <String>[];
    var bytes = 0;
    var truncated = false;

    // Breadth-first so a shallow, wide tree reports progress early.
    final queue = <({String absolute, String relative, int depth})>[
      (absolute: root, relative: '', depth: 0),
    ];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      if (current.depth > limits.maxDepth) {
        truncated = true;
        skipped.add(current.absolute);
        continue;
      }

      final listing = await list(current.absolute);
      switch (listing) {
        case DirectoryContents(:final entries):
          if (current.relative.isNotEmpty) directories.add(current.relative);

          for (final entry in entries) {
            final relative = current.relative.isEmpty
                ? entry.name
                : '${current.relative}/${entry.name}';

            if (entry.isSymlink) {
              unsupported.add(entry.path);
              continue;
            }

            if (entry.isDirectory) {
              queue.add((
                absolute: entry.path,
                relative: relative,
                depth: current.depth + 1,
              ));
              continue;
            }

            // Sockets, fifos, device nodes -- and symlinks, which LIS2
            // reports as mode 0 / unknown rather than S_IFLNK. Recorded so a
            // partial copy is visible instead of silently short.
            if (entry.type != AdbFileType.regular) {
              unsupported.add(entry.path);
              continue;
            }

            if (files.length >= limits.maxFiles ||
                bytes + entry.size > limits.maxBytes) {
              truncated = true;
              continue;
            }

            files.add(WalkedFile(entry, relative));
            bytes += entry.size;
            onProgress?.call(files.length, bytes);
          }

        case DirectoryDenied() || DirectoryFailed():
          skipped.add(current.absolute);

        case DirectoryMissing() || DirectoryNotADirectory():
          // Vanished or changed type mid-walk; nothing to copy.
          break;
      }
    }

    return DirectoryWalk(
      root: root,
      files: files,
      directories: directories,
      skipped: skipped,
      unsupported: unsupported,
      truncated: truncated,
    );
  }

  Future<bool> exists(String path) async => (await stat(path)).exists;

  /// Downloads [remotePath] to [localPath].
  Future<void> pull(
    String remotePath,
    String localPath, {
    void Function(TransferProgress)? onProgress,
  }) => _session.sync.pull(
    RemotePath.normalize(remotePath),
    localPath,
    onProgress: onProgress,
  );

  /// Uploads [localPath] into [remotePath].
  Future<void> push(
    String localPath,
    String remotePath, {
    void Function(TransferProgress)? onProgress,
  }) => _session.sync.push(
    localPath,
    RemotePath.normalize(remotePath),
    onProgress: onProgress,
  );

  Future<void> createDirectory(String path) async {
    // -p so creating an existing directory is not an error, and intermediate
    // components are made as needed.
    await _run('mkdir -p ${PosixShell.quote(RemotePath.normalize(path))}');
  }

  /// Deletes a file or directory. Directories require [recursive].
  Future<void> delete(String path, {bool recursive = false}) async {
    final normalized = RemotePath.normalize(path);
    // Refuse the obviously catastrophic targets outright. The shell would
    // happily run `rm -rf /`, and a UI bug that passes an empty path should
    // not be able to wipe a device.
    if (normalized == RemotePath.root) {
      throw ArgumentError('Refusing to delete the filesystem root');
    }
    await _run('rm ${recursive ? "-rf" : "-f"} ${PosixShell.quote(normalized)}');
  }

  Future<void> deleteAll(
    Iterable<String> paths, {
    bool recursive = false,
  }) async {
    for (final path in paths) {
      await delete(path, recursive: recursive);
    }
  }

  /// Renames or moves [from] to [to].
  Future<void> move(String from, String to) async {
    await _run(
      'mv ${PosixShell.quote(RemotePath.normalize(from))} '
      '${PosixShell.quote(RemotePath.normalize(to))}',
    );
  }

  /// Renames an entry in place, keeping it in the same directory.
  Future<void> rename(String path, String newName) {
    if (newName.contains('/')) {
      throw ArgumentError('A name cannot contain a path separator: $newName');
    }
    final normalized = RemotePath.normalize(path);
    return move(
      normalized,
      RemotePath.join(RemotePath.parent(normalized), newName),
    );
  }

  Future<void> copy(String from, String to, {bool recursive = false}) async {
    await _run(
      'cp ${recursive ? "-r " : ""}'
      '${PosixShell.quote(RemotePath.normalize(from))} '
      '${PosixShell.quote(RemotePath.normalize(to))}',
    );
  }

  /// Total size of a directory tree, in bytes.
  ///
  /// Uses `du` rather than walking the tree over sync: a recursive listing of
  /// a large folder is thousands of round trips, while `du` is one.
  Future<int?> directorySize(String path) async {
    final result = await _run(
      'du -sk ${PosixShell.quote(RemotePath.normalize(path))}',
      allowFailure: true,
    );
    final field = result.trimmed.split(RegExp(r'\s+')).firstOrNull;
    final kilobytes = int.tryParse(field ?? '');
    return kilobytes == null ? null : kilobytes * 1024;
  }

  /// Available and total bytes on the filesystem holding [path].
  Future<({int available, int total})?> freeSpace(String path) async {
    // POSIX output mode gives a single stable line regardless of the busybox
    // or toybox variant behind `df`.
    final result = await _run(
      'df -Pk ${PosixShell.quote(RemotePath.normalize(path))}',
      allowFailure: true,
    );
    final lines = result.stdout.trim().split('\n');
    if (lines.length < 2) return null;

    final fields = lines[1].trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final total = int.tryParse(fields[1]);
    final available = int.tryParse(fields[3]);
    if (total == null || available == null) return null;

    return (available: available * 1024, total: total * 1024);
  }

  Future<ShellResult> _run(String command, {bool allowFailure = false}) async {
    final result = await _session.shell.run(command);
    // shell v1 cannot report status, so a null exit code is not a failure.
    final failed = result.exitCode != null && result.exitCode != 0;
    if (!allowFailure && failed) {
      final message = result.stderr.trim();
      throw AdbFailure(
        message.isEmpty
            ? 'Command failed with exit ${result.exitCode}: $command'
            : message,
      );
    }
    return result;
  }
}
