import 'dart:async';

import 'package:adb_core/adb_core.dart';

import 'logcat_parser.dart';
import 'models/logcat_entry.dart';

/// Which logcat ring buffer to read.
enum LogBuffer {
  main,
  system,
  crash,
  events,
  radio,
  kernel,
  all;

  String get flag => name;
}

/// Reads logcat from a device.
///
/// Streaming is deliberately separate from the UI's buffering: this yields
/// entries as fast as the device produces them, and [LogcatController] is
/// responsible for not repainting per entry.
class LogcatService {
  LogcatService(this._session);

  final AdbSession _session;

  /// Streams entries live until the subscription is cancelled.
  ///
  /// [buffers] defaults to main+system+crash, matching what a developer
  /// usually wants; `events` and `radio` are noisy and rarely useful.
  Stream<LogcatEntry> watch({
    Set<LogBuffer> buffers = const {
      LogBuffer.main,
      LogBuffer.system,
      LogBuffer.crash,
    },
    bool includeExisting = false,
  }) {
    final command = _buildCommand(
      buffers: buffers,
      dump: false,
      tail: includeExisting ? null : 0,
    );
    return _parseStream(_session.shell.stream(command));
  }

  /// Reads what is already in the buffer and returns, without following.
  Future<List<LogcatEntry>> dump({
    Set<LogBuffer> buffers = const {
      LogBuffer.main,
      LogBuffer.system,
      LogBuffer.crash,
    },
    int? tail,
  }) async {
    final command = _buildCommand(buffers: buffers, dump: true, tail: tail);
    final result = await _session.shell.run(command);
    final parser = LogcatParser();
    return result.stdout
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map(parser.parse)
        .toList();
  }

  /// Empties the device-side buffers.
  Future<void> clear({
    Set<LogBuffer> buffers = const {
      LogBuffer.main,
      LogBuffer.system,
      LogBuffer.crash,
    },
  }) async {
    final result = await _session.shell.run(
      _buildCommand(buffers: buffers, dump: false, clear: true),
    );
    // Some devices report a nonzero status even on success; only a message on
    // stderr indicates a real failure.
    if (result.stderr.trim().isNotEmpty) {
      throw AdbFailure('logcat -c failed: ${result.stderr.trim()}');
    }
  }

  String _buildCommand({
    required Set<LogBuffer> buffers,
    required bool dump,
    bool clear = false,
    int? tail,
  }) {
    final parts = <String>['logcat'];

    for (final buffer in buffers) {
      parts..add('-b')..add(buffer.flag);
    }

    if (clear) {
      parts.add('-c');
      return parts.join(' ');
    }

    // threadtime carries pid and tid and is stable across versions; the year
    // modifier removes date guesswork on devices that support it and is
    // ignored by those that do not.
    parts..add('-v')..add('threadtime')..add('-v')..add('year');

    if (dump) parts.add('-d');
    if (tail != null) parts..add('-T')..add('$tail');

    return parts.join(' ');
  }

  /// Reassembles lines across chunk boundaries before parsing.
  Stream<LogcatEntry> _parseStream(Stream<ShellChunk> chunks) async* {
    final assembler = LineAssembler();
    final parser = LogcatParser();

    await for (final chunk in chunks) {
      for (final line in assembler.add(chunk.text)) {
        if (line.isEmpty) continue;
        yield parser.parse(line);
      }
    }

    final tail = assembler.flush();
    if (tail != null && tail.isNotEmpty) yield parser.parse(tail);
  }
}
