import 'models/log_level.dart';
import 'models/logcat_entry.dart';

/// Parses the `threadtime` logcat format, with or without the `year` modifier.
///
///     08-06 10:28:48.123  1234  5678 I ActivityManager: Displayed ...
///     2026-08-06 10:28:48.123  1234  5678 I ActivityManager: Displayed ...
///
/// `threadtime` is the right format to request: it is the only widely
/// available one carrying both pid and tid, and it has been stable across
/// Android versions. Requesting `-v year` alongside it removes the year
/// guesswork, but older devices ignore the modifier, so both shapes parse.
class LogcatParser {
  LogcatParser({DateTime? now}) : _now = now ?? DateTime.now();

  final DateTime _now;

  static final _pattern = RegExp(
    r'^(?:(\d{4})-)?'      // optional year, from -v year
    r'(\d{2})-(\d{2})\s+'  // month-day
    r'(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s+'
    r'(\d+)\s+(\d+)\s+'    // pid, tid
    r'([VDIWEFS])\s+'      // priority
    r'(.*?)\s*:\s'         // tag (non-greedy: tags may contain colons)
    r'(.*)$',              // message
    dotAll: true,
  );

  LogcatEntry parse(String line) {
    final match = _pattern.firstMatch(line);
    if (match == null) return LogcatEntry.unparsed(line);

    final level = LogLevel.fromCode(match.group(10)!);
    if (level == null) return LogcatEntry.unparsed(line);

    return LogcatEntry(
      timestamp: _timestampOf(match),
      pid: int.tryParse(match.group(8)!),
      tid: int.tryParse(match.group(9)!),
      level: level,
      tag: match.group(11)!.trim(),
      message: match.group(12)!,
      raw: line,
    );
  }

  DateTime? _timestampOf(RegExpMatch match) {
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);

    final explicitYear = match.group(1);
    final year = explicitYear != null
        ? int.parse(explicitYear)
        : _inferYear(month, day);

    try {
      return DateTime(
        year,
        month,
        day,
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        int.parse(match.group(7)!),
      );
    } on Object {
      // A malformed date must not cost us the message.
      return null;
    }
  }

  /// `threadtime` omits the year. Assume the current one, except when the
  /// entry's date is in the future relative to now — that means we are reading
  /// December logs in January, so it belongs to the previous year.
  int _inferYear(int month, int day) {
    final candidate = DateTime(_now.year, month, day);
    // One day of slack absorbs clock skew and timezone offsets between the
    // device and this machine.
    if (candidate.isAfter(_now.add(const Duration(days: 1)))) {
      return _now.year - 1;
    }
    return _now.year;
  }
}

/// Splits a byte-chunk stream into lines.
///
/// Logcat chunks arrive on socket boundaries, not line boundaries — a single
/// line is routinely split across two reads. Anything that parses per chunk
/// instead of per line will corrupt entries under load, which is exactly when
/// logs matter.
class LineAssembler {
  final StringBuffer _partial = StringBuffer();

  /// Returns the complete lines in [chunk], holding any trailing fragment
  /// until the rest arrives.
  List<String> add(String chunk) {
    final lines = <String>[];
    var start = 0;

    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != '\n') continue;
      var line = chunk.substring(start, i);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (_partial.isNotEmpty) {
        line = '${_partial}$line';
        _partial.clear();
      }
      lines.add(line);
      start = i + 1;
    }

    if (start < chunk.length) _partial.write(chunk.substring(start));
    return lines;
  }

  /// Any buffered fragment, for when the stream ends without a final newline.
  String? flush() {
    if (_partial.isEmpty) return null;
    final rest = _partial.toString();
    _partial.clear();
    return rest;
  }
}
