import 'log_level.dart';

/// One parsed logcat line.
class LogcatEntry {
  const LogcatEntry({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    required this.raw,
  });

  /// A line that did not match the expected format, kept verbatim.
  ///
  /// Logcat interleaves banners ("--------- beginning of main"), native
  /// crash dumps, and multi-line stack traces with normal entries. Dropping
  /// them would silently hide the most important output in the buffer, so
  /// they are surfaced as unparsed instead.
  const LogcatEntry.unparsed(this.raw)
    : timestamp = null,
      pid = null,
      tid = null,
      level = null,
      tag = null,
      message = raw;

  final DateTime? timestamp;
  final int? pid;
  final int? tid;
  final LogLevel? level;
  final String? tag;
  final String message;
  final String raw;

  bool get isParsed => level != null;

  /// Continuation lines of a stack trace start with whitespace and belong
  /// visually with the entry above them.
  bool get isContinuation => !isParsed && raw.startsWith(RegExp(r'\s'));

  @override
  String toString() => raw;
}
