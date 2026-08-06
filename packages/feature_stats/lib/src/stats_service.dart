import 'dart:async';

import 'package:adb_core/adb_core.dart';

import 'models/battery_stats.dart';
import 'models/cpu_stats.dart';
import 'models/memory_stats.dart';
import 'stats_parsers.dart';

/// One poll of the device.
class DeviceStats {
  const DeviceStats({
    required this.sampledAt,
    required this.cpu,
    required this.memory,
    required this.battery,
    this.uptime,
  });

  final DateTime sampledAt;
  final CpuUsage cpu;
  final MemoryStats memory;
  final BatteryStats battery;
  final Duration? uptime;
}

/// Polls CPU, memory, and battery.
///
/// Everything is fetched in a *single* shell invocation per tick. Each
/// `openService` costs a socket connect and a `host:transport` round trip, so
/// four separate commands at 1 Hz is four times the overhead for data that
/// must be sampled at the same instant to be coherent.
class StatsService {
  StatsService(this._session);

  final AdbSession _session;

  /// Previous CPU counters. Usage is a delta, so the first sample has none.
  List<CpuSnapshot>? _previousCpu;

  static const _delimiter = '###ADBSTATS###';

  /// `dumpsys battery` is the slow part; the /proc reads are nearly free.
  static const _command =
      'echo $_delimiter; cat /proc/stat; '
      'echo $_delimiter; cat /proc/meminfo; '
      'echo $_delimiter; cat /proc/uptime; '
      'echo $_delimiter; dumpsys battery';

  /// Takes one sample. The first call returns null CPU usage — there is no
  /// earlier reading to diff against.
  Future<DeviceStats> sample() async {
    final result = await _session.shell.run(_command);
    if (result.exitCode != null && result.exitCode != 0 &&
        result.stdout.trim().isEmpty) {
      throw AdbFailure(
        'stats command failed (exit ${result.exitCode}): '
        '${result.stderr.trim()}',
      );
    }

    final sections = result.stdout.split(_delimiter);
    // Leading empty section before the first delimiter, then four bodies.
    String section(int index) =>
        index + 1 < sections.length ? sections[index + 1] : '';

    final currentCpu = StatsParsers.parseProcStat(section(0));
    final usage = _previousCpu == null
        ? CpuUsage.unknown
        : StatsParsers.diffCpu(_previousCpu!, currentCpu);
    _previousCpu = currentCpu;

    return DeviceStats(
      sampledAt: DateTime.now(),
      cpu: usage,
      memory: StatsParsers.parseMemInfo(section(1)),
      uptime: StatsParsers.parseUptime(section(2)),
      battery: StatsParsers.parseBattery(section(3)),
    );
  }

  /// Samples every [interval] until the subscription is cancelled.
  ///
  /// Ticks are sequential, not timer-driven: if a sample takes longer than the
  /// interval (a busy device, a slow `dumpsys`), a timer-based loop would
  /// queue overlapping shells and make things worse.
  Stream<DeviceStats> watch({
    Duration interval = const Duration(seconds: 1),
  }) async* {
    while (true) {
      final started = DateTime.now();
      yield await sample();

      final elapsed = DateTime.now().difference(started);
      final remaining = interval - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }
  }

  /// Discards the CPU baseline, so the next sample starts a fresh delta.
  /// Call after a reconnect — counters reset when the device reboots.
  void resetBaseline() => _previousCpu = null;
}
