import 'dart:io';

import 'package:adb_files/build_info.dart';
import 'package:adb_files/screens/settings_view.dart';
import 'package:adb_files/state/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;
  late AppSettings settings;

  setUp(() async {
    // A temp file, never the real one: an earlier version of these tests
    // wrote to the user's actual preferences and changed their theme.
    dir = await Directory.systemTemp.createTemp('adb_files_settings_view');
    file = File('${dir.path}/settings.json');
    settings = await AppSettings.load(file: file);
  });

  tearDown(() async {
    BuildInfo.debugSet(null);
    // The theme picker fires its save without awaiting it. Windows cannot
    // delete a directory holding a file with an open handle, so skipping this
    // fails on Windows CI while passing on macOS and Linux.
    await settings.flush();
    await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SettingsView(settings: settings))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the running build in the About section', (tester) async {
    BuildInfo.debugSet(
      const BuildInfo(version: '0.1.0', buildNumber: '3', commit: '452b254'),
    );
    await pump(tester);

    expect(find.text('About'.toUpperCase()), findsOneWidget);
    expect(find.text('0.1.0 (3) · 452b254'), findsOneWidget);
  });

  testWidgets('shows the build date when one was compiled in', (tester) async {
    BuildInfo.debugSet(
      BuildInfo(
        version: '0.1.0',
        buildNumber: '3',
        builtAt: DateTime.utc(2026, 8, 7, 9, 0),
      ),
    );
    await pump(tester);

    expect(find.textContaining('Built '), findsOneWidget);
    expect(find.textContaining('Aug 2026'), findsOneWidget);
  });

  testWidgets('copies diagnostics to the clipboard', (tester) async {
    BuildInfo.debugSet(
      const BuildInfo(version: '0.1.0', buildNumber: '3', commit: '452b254'),
    );

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pump(tester);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, contains('adb_files 0.1.0 (3)'));
    expect(copied, contains('commit: 452b254'));
    // Confirms the button acknowledges the copy rather than looking inert.
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('theme picker reflects and updates the stored mode',
      (tester) async {
    BuildInfo.debugSet(const BuildInfo(version: '0.1.0', buildNumber: '3'));
    await pump(tester);

    expect(settings.themeMode, ThemeMode.system);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);

    // The choice is only useful if it survives a relaunch, so assert the file
    // rather than just the in-memory value.
    await settings.flush();
    expect((await AppSettings.load(file: file)).themeMode, ThemeMode.dark);
  });
}
