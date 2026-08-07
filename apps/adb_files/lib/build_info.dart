import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// Identifies exactly which build of the app is running.
///
/// Two halves, from two places:
///
///  * `version` and `buildNumber` come from the bundle at runtime, which is
///    the same value the OS shows in Finder's Get Info and in
///    Add/Remove Programs — so they cannot drift from what the installer says.
///  * `commit`, `dirty`, and `builtAt` are compile-time constants injected by
///    `tool/release.sh` via `--dart-define`. A bundle version alone cannot
///    tell you *which* build of `0.1.0` a user is running; the commit can.
///
/// Nothing here is generated into a source file, so a build never dirties the
/// working tree — which matters, because the `dirty` flag would then always
/// report true.
class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.buildNumber,
    this.commit = '',
    this.dirty = false,
    this.builtAt,
  });

  /// Semantic version, e.g. `0.1.0`. Owned by `pubspec.yaml`.
  final String version;

  /// Monotonic build number. The release script derives this from the git
  /// commit count, so it advances on its own with every commit.
  final String buildNumber;

  /// Short commit hash, or empty for a build made outside the release script.
  final String commit;

  /// True when the tree had uncommitted changes at build time. Always expect
  /// this on local development builds.
  final bool dirty;

  final DateTime? builtAt;

  static const _commit = String.fromEnvironment('GIT_COMMIT');
  static const _dirty = bool.fromEnvironment('GIT_DIRTY');
  static const _builtAt = String.fromEnvironment('BUILD_TIME');

  static Future<BuildInfo>? _pending;

  /// Reads the running bundle's version. Cached: the platform channel round
  /// trip is pointless to repeat, and this is read from several places.
  static Future<BuildInfo> load() => _pending ??= _load();

  static Future<BuildInfo> _load() async {
    var version = '';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } on Object {
      // Not worth failing over: the compile-time half is still useful, and an
      // unknown version reads better than a crash in an About box.
    }
    return BuildInfo(
      version: version,
      buildNumber: buildNumber,
      commit: _commit,
      dirty: _dirty,
      builtAt: DateTime.tryParse(_builtAt),
    );
  }

  /// Replaces the cached value. For tests only.
  static void debugSet(BuildInfo? info) =>
      _pending = info == null ? null : Future.value(info);

  /// `0.1.0 (4)` — what belongs next to the app name.
  String get shortLabel {
    if (version.isEmpty) return 'unknown version';
    return buildNumber.isEmpty ? version : '$version ($buildNumber)';
  }

  /// `0.1.0 (4) · 452b254` — adds provenance, for a bug report.
  String get detailLabel {
    final parts = <String>[shortLabel];
    if (commit.isNotEmpty) parts.add(dirty ? '$commit-dirty' : commit);
    if (commit.isEmpty) parts.add('local build');
    return parts.join(' · ');
  }

  /// A block worth pasting into a bug report. The OS build is included
  /// because most of what goes wrong here is platform-specific.
  String get diagnostics => [
    'adb_files $shortLabel',
    if (commit.isNotEmpty) 'commit: $commit${dirty ? ' (dirty)' : ''}',
    if (builtAt != null) 'built: ${builtAt!.toUtc().toIso8601String()}',
    'platform: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
  ].join('\n');
}
