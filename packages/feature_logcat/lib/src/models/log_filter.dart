import 'log_level.dart';
import 'logcat_entry.dart';

/// A predicate over log entries, built from the controls a log view exposes.
///
/// Immutable so it can be compared cheaply — the controller re-runs the whole
/// buffer through the filter only when this actually changes.
class LogFilter {
  const LogFilter({
    this.minLevel = LogLevel.verbose,
    this.query = '',
    this.tags = const {},
    this.pids = const {},
    this.useRegex = false,
    this.caseSensitive = false,
    this.includeUnparsed = true,
  });

  final LogLevel minLevel;

  /// Free text matched against tag and message.
  final String query;

  /// When non-empty, only these tags pass.
  final Set<String> tags;

  /// When non-empty, only these process ids pass.
  final Set<int> pids;

  final bool useRegex;
  final bool caseSensitive;

  /// Stack traces and banners have no level or tag. Excluding them hides
  /// crash output, so they pass by default.
  final bool includeUnparsed;

  static const empty = LogFilter();

  bool get isActive =>
      minLevel != LogLevel.verbose ||
      query.isNotEmpty ||
      tags.isNotEmpty ||
      pids.isNotEmpty;

  /// Compiled once per filter rather than per line — a regex rebuilt 12,000
  /// times a second is a real cost.
  RegExp? get _regex {
    if (!useRegex || query.isEmpty) return null;
    try {
      return RegExp(query, caseSensitive: caseSensitive);
    } on FormatException {
      // A half-typed regex should show everything, not throw at the user.
      return null;
    }
  }

  /// True when [entry] should be displayed.
  bool matches(LogcatEntry entry, {RegExp? compiledRegex}) {
    if (!entry.isParsed) return includeUnparsed;

    if (!entry.level!.atLeast(minLevel)) return false;
    if (tags.isNotEmpty && !tags.contains(entry.tag)) return false;
    if (pids.isNotEmpty && !pids.contains(entry.pid)) return false;
    if (query.isEmpty) return true;

    final regex = compiledRegex ?? _regex;
    if (regex != null) {
      return regex.hasMatch(entry.message) ||
          regex.hasMatch(entry.tag ?? '');
    }

    final needle = caseSensitive ? query : query.toLowerCase();
    final tag = caseSensitive ? (entry.tag ?? '') : (entry.tag ?? '').toLowerCase();
    final message =
        caseSensitive ? entry.message : entry.message.toLowerCase();
    return message.contains(needle) || tag.contains(needle);
  }

  /// Returns the compiled regex so a batch filter run can reuse it.
  RegExp? compile() => _regex;

  LogFilter copyWith({
    LogLevel? minLevel,
    String? query,
    Set<String>? tags,
    Set<int>? pids,
    bool? useRegex,
    bool? caseSensitive,
    bool? includeUnparsed,
  }) => LogFilter(
    minLevel: minLevel ?? this.minLevel,
    query: query ?? this.query,
    tags: tags ?? this.tags,
    pids: pids ?? this.pids,
    useRegex: useRegex ?? this.useRegex,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    includeUnparsed: includeUnparsed ?? this.includeUnparsed,
  );

  @override
  bool operator ==(Object other) =>
      other is LogFilter &&
      other.minLevel == minLevel &&
      other.query == query &&
      other.useRegex == useRegex &&
      other.caseSensitive == caseSensitive &&
      other.includeUnparsed == includeUnparsed &&
      _setEquals(other.tags, tags) &&
      _setEquals(other.pids, pids);

  @override
  int get hashCode => Object.hash(
    minLevel,
    query,
    useRegex,
    caseSensitive,
    includeUnparsed,
    Object.hashAllUnordered(tags),
    Object.hashAllUnordered(pids),
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
