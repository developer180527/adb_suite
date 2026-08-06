/// Android log priority, ordered so comparisons work as a threshold filter.
enum LogLevel implements Comparable<LogLevel> {
  verbose('V', 'Verbose'),
  debug('D', 'Debug'),
  info('I', 'Info'),
  warn('W', 'Warn'),
  error('E', 'Error'),
  fatal('F', 'Fatal');

  const LogLevel(this.code, this.label);

  /// The single letter logcat emits.
  final String code;
  final String label;

  static LogLevel? fromCode(String code) {
    for (final level in values) {
      if (level.code == code) return level;
    }
    // 'S' (silent) is a filter threshold, never an emitted priority.
    return null;
  }

  /// True when this level should show under a [minimum] threshold filter.
  bool atLeast(LogLevel minimum) => index >= minimum.index;

  @override
  int compareTo(LogLevel other) => index - other.index;
}
