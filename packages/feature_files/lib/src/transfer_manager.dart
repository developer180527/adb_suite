import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:flutter/foundation.dart';

import 'directory_walk.dart';
import 'file_service.dart';
import 'remote_path.dart';

enum TransferDirection { pull, push }

enum TransferState { queued, running, completed, failed, cancelled }

/// One queued file transfer.
class TransferJob {
  TransferJob({
    required this.id,
    required this.direction,
    required this.remotePath,
    required this.localPath,
  });

  final int id;
  final TransferDirection direction;
  final String remotePath;
  final String localPath;

  TransferState state = TransferState.queued;
  int bytes = 0;
  int? total;
  Object? error;
  DateTime? startedAt;
  DateTime? finishedAt;

  /// Display name: the remote basename for a pull, the local one for a push.
  String get name => direction == TransferDirection.pull
      ? RemotePath.basename(remotePath)
      : _localBasename(localPath);

  /// Splits on both separators so a Windows host path works too.
  static String _localBasename(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }

  double? get fraction {
    final t = total;
    if (t == null) return null;
    if (t == 0) return 1.0;
    return (bytes / t).clamp(0.0, 1.0);
  }

  bool get isFinished =>
      state == TransferState.completed ||
      state == TransferState.failed ||
      state == TransferState.cancelled;

  /// Bytes per second, or null when there is not enough signal yet.
  ///
  /// A running transfer needs a moment before the number stops jumping around,
  /// but a *finished* one always has a usable figure — and at USB speeds most
  /// transfers finish fast enough that a long warm-up would suppress the rate
  /// entirely. A 4 MiB push completes in about 150 ms on a Galaxy A71.
  int? get rate {
    final started = startedAt;
    if (started == null || bytes == 0) return null;

    final ended = finishedAt;
    final elapsed = (ended ?? DateTime.now()).difference(started);
    if (elapsed.inMicroseconds <= 0) return null;
    if (ended == null && elapsed.inMilliseconds < 200) return null;

    return (bytes * 1000000 / elapsed.inMicroseconds).round();
  }
}

/// Runs transfers one at a time and reports progress.
///
/// Serialised on purpose. Each transfer already saturates the USB link (~32
/// MB/s measured), so running several concurrently just interleaves them and
/// makes every individual progress bar crawl, which reads as "stuck" to a
/// user.
class TransferManager extends ChangeNotifier {
  TransferManager(this._service);

  final FileService _service;
  final Queue<TransferJob> _pending = Queue();
  final List<TransferJob> _all = [];

  int _nextId = 1;
  bool _draining = false;
  TransferJob? _current;
  bool _cancelRequested = false;

  List<TransferJob> get jobs => List.unmodifiable(_all);
  TransferJob? get current => _current;

  Iterable<TransferJob> get active => _all.where((j) => !j.isFinished);
  Iterable<TransferJob> get finished => _all.where((j) => j.isFinished);

  bool get isBusy => _current != null || _pending.isNotEmpty;

  int get pendingCount => _pending.length + (_current == null ? 0 : 1);

  /// Overall progress across unfinished jobs, or null when sizes are unknown.
  double? get overallFraction {
    final tracked = active.where((j) => j.total != null).toList();
    if (tracked.isEmpty) return null;
    final done = tracked.fold<int>(0, (sum, j) => sum + j.bytes);
    final total = tracked.fold<int>(0, (sum, j) => sum + j.total!);
    return total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
  }

  TransferJob enqueuePull(String remotePath, String localPath) =>
      _enqueue(TransferDirection.pull, remotePath, localPath);

  TransferJob enqueuePush(String localPath, String remotePath) =>
      _enqueue(TransferDirection.push, remotePath, localPath);

  /// Expands a device folder into one job per file, recreating the tree under
  /// [localRoot].
  ///
  /// The walk happens up front so the queue length and total size are known
  /// before anything transfers — a copy that reveals its size gradually is
  /// impossible to judge.
  Future<DirectoryWalk> enqueueDirectoryPull(
    String remoteDir,
    String localRoot, {
    void Function(int files, int bytes)? onScanProgress,
    WalkLimits limits = const WalkLimits(),
  }) async {
    final walk = await _service.walkDirectory(
      remoteDir,
      limits: limits,
      onProgress: onScanProgress,
    );

    final destination = Directory(
      '$localRoot/${RemotePath.basename(walk.root)}',
    );
    // Create every directory first, including empty ones, so the copy mirrors
    // the source rather than quietly dropping empty folders.
    destination.createSync(recursive: true);
    for (final relative in walk.directories) {
      Directory('${destination.path}/$relative').createSync(recursive: true);
    }

    for (final file in walk.files) {
      enqueuePull(file.entry.path, '${destination.path}/${file.relativePath}');
    }

    return walk;
  }

  /// Uploads a local folder, recreating the tree under [remoteRoot].
  ///
  /// Returns the number of files queued.
  Future<int> enqueueDirectoryPush(
    String localDir,
    String remoteRoot, {
    void Function(int files)? onScanProgress,
  }) async {
    final source = Directory(localDir);
    if (!source.existsSync()) return 0;

    final base = localDir.endsWith(Platform.pathSeparator)
        ? localDir.substring(0, localDir.length - 1)
        : localDir;
    final folderName = TransferJob._localBasename(base);
    final remoteBase = RemotePath.join(remoteRoot, folderName);

    // Directories must exist before their files land, and the queue runs in
    // order, so create them all here rather than interleaving mkdir jobs.
    final directories = <String>{remoteBase};
    final files = <({String local, String remote})>[];

    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = entity.path
          .substring(base.length + 1)
          .replaceAll(Platform.pathSeparator, '/');

      if (entity is Directory) {
        directories.add(RemotePath.join(remoteBase, relative));
      } else if (entity is File) {
        files.add((
          local: entity.path,
          remote: RemotePath.join(remoteBase, relative),
        ));
        onScanProgress?.call(files.length);
      }
      // Links are skipped: `followLinks: false` means they arrive as Link,
      // and pushing the link itself is not something the sync protocol does.
    }

    // Shortest first, so parents precede children.
    final ordered = directories.toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final directory in ordered) {
      await _service.createDirectory(directory);
    }

    for (final file in files) {
      enqueuePush(file.local, file.remote);
    }

    return files.length;
  }

  TransferJob _enqueue(
    TransferDirection direction,
    String remotePath,
    String localPath,
  ) {
    final job = TransferJob(
      id: _nextId++,
      direction: direction,
      remotePath: remotePath,
      localPath: localPath,
    );
    _all.add(job);
    _pending.add(job);
    notifyListeners();
    unawaited(_drain());
    return job;
  }

  /// Cancels a queued job, or requests cancellation of the running one.
  ///
  /// A running transfer stops at the next progress callback rather than
  /// mid-write, so the partial file is closed cleanly.
  void cancel(TransferJob job) {
    if (job.isFinished) return;
    if (identical(job, _current)) {
      _cancelRequested = true;
    } else {
      _pending.remove(job);
      job.state = TransferState.cancelled;
    }
    notifyListeners();
  }

  void cancelAll() {
    for (final job in _pending) {
      job.state = TransferState.cancelled;
    }
    _pending.clear();
    if (_current != null) _cancelRequested = true;
    notifyListeners();
  }

  /// Drops finished entries from the visible list.
  void clearFinished() {
    _all.removeWhere((j) => j.isFinished);
    notifyListeners();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;

    try {
      while (_pending.isNotEmpty) {
        final job = _pending.removeFirst();
        if (job.state == TransferState.cancelled) continue;

        _current = job;
        _cancelRequested = false;
        job.state = TransferState.running;
        job.startedAt = DateTime.now();
        notifyListeners();

        try {
          void onProgress(TransferProgress p) {
            job.bytes = p.bytes;
            job.total = p.total;
            if (_cancelRequested) throw const _Cancelled();
            notifyListeners();
          }

          if (job.direction == TransferDirection.pull) {
            await _service.pull(
              job.remotePath,
              job.localPath,
              onProgress: onProgress,
            );
          } else {
            await _service.push(
              job.localPath,
              job.remotePath,
              onProgress: onProgress,
            );
          }
          job.state = TransferState.completed;
        } on _Cancelled {
          job.state = TransferState.cancelled;
        } on Object catch (e) {
          job.state = TransferState.failed;
          job.error = e;
        } finally {
          job.finishedAt = DateTime.now();
          _current = null;
          notifyListeners();
        }
      }
    } finally {
      _draining = false;
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
