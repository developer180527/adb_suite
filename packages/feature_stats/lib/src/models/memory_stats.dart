/// A snapshot of `/proc/meminfo`, in bytes.
class MemoryStats {
  const MemoryStats({
    required this.total,
    required this.free,
    required this.available,
    required this.buffers,
    required this.cached,
    required this.swapTotal,
    required this.swapFree,
  });

  final int total;
  final int free;

  /// Kernel's own estimate of what a new process could claim without
  /// swapping. This is the number that reflects real pressure — `free` looks
  /// alarmingly low on Android because the page cache is doing its job.
  final int available;

  final int buffers;
  final int cached;
  final int swapTotal;
  final int swapFree;

  /// Memory genuinely in use, based on [available] rather than [free].
  int get used => total - available;

  double get usedFraction => total == 0 ? 0 : (used / total).clamp(0.0, 1.0);

  int get swapUsed => swapTotal - swapFree;

  double get swapUsedFraction =>
      swapTotal == 0 ? 0 : (swapUsed / swapTotal).clamp(0.0, 1.0);

  static const empty = MemoryStats(
    total: 0,
    free: 0,
    available: 0,
    buffers: 0,
    cached: 0,
    swapTotal: 0,
    swapFree: 0,
  );
}
