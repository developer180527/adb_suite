import 'package:adb_files/state/app_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOptions.parse', () {
    test('no arguments means the default start path', () {
      expect(AppOptions.parse([]).initialPath, isNull);
    });

    test('reads the path a detached tab carries over', () {
      expect(
        AppOptions.parse(['--path=/sdcard/DCIM/Camera']).initialPath,
        '/sdcard/DCIM/Camera',
      );
    });

    test('ignores the geometry flags, which the native side consumes', () {
      final options = AppOptions.parse([
        '--width=1180',
        '--height=760',
        '--path=/sdcard/Download',
        '--x=40',
        '--y=90',
      ]);
      expect(options.initialPath, '/sdcard/Download');
    });

    test('an empty path is treated as absent', () {
      // Better to fall back to the default than open a tab at "".
      expect(AppOptions.parse(['--path=']).initialPath, isNull);
    });

    test('unknown arguments are ignored', () {
      // Flutter and macOS both inject their own flags on launch.
      expect(
        AppOptions.parse([
          '--enable-dart-profiling',
          '-psn_0_12345',
          '--path=/sdcard',
        ]).initialPath,
        '/sdcard',
      );
    });

    test('a path containing spaces survives', () {
      expect(
        AppOptions.parse(['--path=/sdcard/My Files/A B']).initialPath,
        '/sdcard/My Files/A B',
      );
    });
  });

  group('AppOptions.buildArgs', () {
    test('rounds sizes and includes the path', () {
      final args = AppOptions.buildArgs(
        path: '/sdcard/DCIM',
        width: 1180.4,
        height: 760.6,
      );
      expect(args, containsAll(<String>[
        '--path=/sdcard/DCIM',
        '--width=1180',
        '--height=761',
      ]));
    });

    test('omits position when not supplied', () {
      final args = AppOptions.buildArgs(
        path: '/sdcard',
        width: 800,
        height: 600,
      );
      expect(args.any((a) => a.startsWith('--x=')), isFalse);
      expect(args.any((a) => a.startsWith('--y=')), isFalse);
    });

    test('round-trips through parse', () {
      // The two sides must agree, since they are separate processes.
      final args = AppOptions.buildArgs(
        path: '/sdcard/Movies',
        width: 1000,
        height: 700,
      );
      expect(AppOptions.parse(args).initialPath, '/sdcard/Movies');
    });

    test('every geometry flag it emits is one the native side knows', () {
      final args = AppOptions.buildArgs(
        path: '/sdcard',
        width: 900,
        height: 650,
        x: 10,
        y: 20,
      );
      final geometry = args.where((a) => !a.startsWith('--path='));
      for (final arg in geometry) {
        expect(
          AppOptions.geometryFlags.any(arg.startsWith),
          isTrue,
          reason: '$arg is not read by MainFlutterWindow.swift',
        );
      }
    });
  });
}
