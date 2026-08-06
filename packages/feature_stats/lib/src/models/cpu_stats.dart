/// Raw cumulative jiffie counters for one CPU line of `/proc/stat`.
///
/// These are monotonically increasing totals since boot, so a single reading
/// says nothing about current load — usage is always a delta between two.
class CpuSnapshot {
  const CpuSnapshot({
    required this.name,
    required this.user,
    required this.nice,
    required this.system,
    required this.idle,
    required this.iowait,
    required this.irq,
    required this.softirq,
    required this.steal,
  });

  final String name;
  final int user;
  final int nice;
  final int system;
  final int idle;
  final int iowait;
  final int irq;
  final int softirq;
  final int steal;

  /// iowait counts as idle: the CPU was not doing work.
  int get idleTotal => idle + iowait;

  int get busyTotal => user + nice + system + irq + softirq + steal;

  int get total => idleTotal + busyTotal;

  /// Fraction busy between this snapshot and an earlier one, 0.0–1.0.
  ///
  /// Returns null when the delta is not usable — the counters reset (device
  /// rebooted) or no time passed between samples.
  double? usageSince(CpuSnapshot previous) {
    final totalDelta = total - previous.total;
    final idleDelta = idleTotal - previous.idleTotal;
    if (totalDelta <= 0 || idleDelta < 0) return null;
    return ((totalDelta - idleDelta) / totalDelta).clamp(0.0, 1.0);
  }

  bool get isAggregate => name == 'cpu';
}

/// Computed usage across the whole device and per core.
class CpuUsage {
  const CpuUsage({required this.overall, required this.perCore});

  /// 0.0–1.0 across all cores, or null on the first sample when there is no
  /// previous reading to diff against.
  final double? overall;

  /// Per-core usage, index matching `cpu0`, `cpu1`, … Cores that are offline
  /// (common on big.LITTLE under light load) are absent from `/proc/stat`
  /// entirely, so this list can be shorter than the physical core count.
  final List<double?> perCore;

  int get coreCount => perCore.length;

  static const unknown = CpuUsage(overall: null, perCore: []);
}
