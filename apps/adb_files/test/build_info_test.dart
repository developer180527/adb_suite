import 'package:adb_files/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildInfo labels', () {
    test('combines version and build number', () {
      const info = BuildInfo(version: '0.1.0', buildNumber: '4');
      expect(info.shortLabel, '0.1.0 (4)');
    });

    test('omits an empty build number rather than showing "()"', () {
      const info = BuildInfo(version: '0.1.0', buildNumber: '');
      expect(info.shortLabel, '0.1.0');
    });

    test('degrades to a readable string when the bundle read failed', () {
      const info = BuildInfo(version: '', buildNumber: '');
      expect(info.shortLabel, 'unknown version');
    });

    test('appends the commit when one was compiled in', () {
      const info =
          BuildInfo(version: '0.1.0', buildNumber: '4', commit: '452b254');
      expect(info.detailLabel, '0.1.0 (4) · 452b254');
    });

    test('marks a dirty tree, so a local build is never mistaken for a release',
        () {
      const info = BuildInfo(
        version: '0.1.0',
        buildNumber: '4',
        commit: '452b254',
        dirty: true,
      );
      expect(info.detailLabel, contains('452b254-dirty'));
    });

    test('says "local build" when no commit was injected', () {
      const info = BuildInfo(version: '0.1.0', buildNumber: '1');
      expect(info.detailLabel, '0.1.0 (1) · local build');
    });
  });

  group('BuildInfo diagnostics', () {
    test('carries version, commit and build time for a bug report', () {
      final info = BuildInfo(
        version: '0.1.0',
        buildNumber: '4',
        commit: '452b254',
        builtAt: DateTime.utc(2026, 8, 7, 14, 3),
      );
      final text = info.diagnostics;
      expect(text, contains('adb_files 0.1.0 (4)'));
      expect(text, contains('commit: 452b254'));
      expect(text, contains('2026-08-07T14:03:00.000Z'));
      expect(text, contains('platform:'));
    });

    test('omits commit and build time when they are unknown', () {
      const info = BuildInfo(version: '0.1.0', buildNumber: '1');
      expect(info.diagnostics, isNot(contains('commit:')));
      expect(info.diagnostics, isNot(contains('built:')));
    });
  });

  group('BuildInfo.load', () {
    tearDown(() => BuildInfo.debugSet(null));

    test('caches, so repeated reads do not re-cross the platform channel', () {
      const info = BuildInfo(version: '9.9.9', buildNumber: '7');
      BuildInfo.debugSet(info);
      expect(identical(BuildInfo.load(), BuildInfo.load()), isTrue);
    });

    test('survives a platform channel that is unavailable in tests', () async {
      // No binding is registered for package_info_plus here, so this exercises
      // the same path as a bundle whose Info.plist cannot be read.
      TestWidgetsFlutterBinding.ensureInitialized();
      final info = await BuildInfo.load();
      expect(info.version, isA<String>());
    });
  });
}
