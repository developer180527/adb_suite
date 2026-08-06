import 'models/battery_stats.dart';
import 'models/cpu_stats.dart';
import 'models/memory_stats.dart';

/// Parsers for the `/proc` and `dumpsys` text this feature samples.
///
/// Kept as pure functions over strings so every format quirk is testable
/// against captured output, with no device in the loop.
class StatsParsers {
  const StatsParsers._();

  /// Parses `/proc/stat`.
  ///
  /// Lines look like:
  ///
  ///     cpu  1234 56 789 98765 43 21 9 0 0 0
  ///     cpu0 ...
  ///
  /// Fields after `softirq`/`steal` (guest, guest_nice) are already counted
  /// inside `user`/`nice` by the kernel, so including them would double-count.
  static List<CpuSnapshot> parseProcStat(String text) {
    final snapshots = <CpuSnapshot>[];

    for (final line in text.split('\n')) {
      if (!line.startsWith('cpu')) continue;

      final fields = line.trim().split(RegExp(r'\s+'));
      // name + at least user/nice/system/idle
      if (fields.length < 5) continue;

      int at(int index) =>
          index < fields.length ? (int.tryParse(fields[index]) ?? 0) : 0;

      snapshots.add(
        CpuSnapshot(
          name: fields[0],
          user: at(1),
          nice: at(2),
          system: at(3),
          idle: at(4),
          iowait: at(5),
          irq: at(6),
          softirq: at(7),
          steal: at(8),
        ),
      );
    }

    return snapshots;
  }

  /// Computes usage between two `/proc/stat` readings.
  ///
  /// Matches cores by name rather than position: a core that goes offline
  /// between samples disappears from the file, and index-matching would then
  /// silently attribute one core's load to another.
  static CpuUsage diffCpu(
    List<CpuSnapshot> previous,
    List<CpuSnapshot> current,
  ) {
    final before = {for (final s in previous) s.name: s};

    double? overall;
    final perCore = <double?>[];

    for (final snapshot in current) {
      final earlier = before[snapshot.name];
      final usage = earlier == null ? null : snapshot.usageSince(earlier);
      if (snapshot.isAggregate) {
        overall = usage;
      } else {
        perCore.add(usage);
      }
    }

    return CpuUsage(overall: overall, perCore: perCore);
  }

  /// Parses `/proc/meminfo`. Values are `kB` in the file; returned as bytes.
  static MemoryStats parseMemInfo(String text) {
    final values = <String, int>{};

    for (final line in text.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      final rest = line.substring(colon + 1).trim();
      final number = int.tryParse(rest.split(RegExp(r'\s+')).first);
      if (number == null) continue;
      // Every field of interest is reported in kB; the suffix is uniform.
      values[key] = number * 1024;
    }

    final total = values['MemTotal'] ?? 0;
    final free = values['MemFree'] ?? 0;

    return MemoryStats(
      total: total,
      free: free,
      // Pre-3.14 kernels lack MemAvailable. Approximate it the way `free(1)`
      // does rather than reporting zero available memory.
      available: values['MemAvailable'] ??
          (free + (values['Buffers'] ?? 0) + (values['Cached'] ?? 0)),
      buffers: values['Buffers'] ?? 0,
      cached: values['Cached'] ?? 0,
      swapTotal: values['SwapTotal'] ?? 0,
      swapFree: values['SwapFree'] ?? 0,
    );
  }

  /// Parses `dumpsys battery`, whose body is `  key: value` lines.
  static BatteryStats parseBattery(String text) {
    final values = <String, String>{};

    for (final line in text.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      values[line.substring(0, colon).trim()] =
          line.substring(colon + 1).trim();
    }

    int? number(String key) => int.tryParse(values[key] ?? '');
    bool flag(String key) => values[key] == 'true';

    // Reported in tenths of a degree Celsius.
    final rawTemp = number('temperature') ?? 0;

    // Nearly all devices report millivolts, but a few report microvolts.
    // Anything above 100000 cannot be millivolts for a phone battery.
    var voltage = number('voltage') ?? 0;
    if (voltage > 100000) voltage ~/= 1000;

    return BatteryStats(
      level: number('level') ?? 0,
      scale: number('scale') ?? 100,
      status: BatteryStatus.fromCode(number('status')),
      health: BatteryHealth.fromCode(number('health')),
      temperature: rawTemp / 10.0,
      voltage: voltage,
      acPowered: flag('AC powered'),
      usbPowered: flag('USB powered'),
      technology: values['technology']?.isEmpty ?? true
          ? null
          : values['technology'],
    );
  }

  /// Parses `/proc/uptime`, whose first field is seconds since boot.
  static Duration? parseUptime(String text) {
    final first = text.trim().split(RegExp(r'\s+')).firstOrNull;
    final seconds = double.tryParse(first ?? '');
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }
}
