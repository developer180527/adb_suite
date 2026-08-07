import 'dart:convert';
import 'dart:io';

import 'package:adb_files/state/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  // Every test uses its own file. An earlier version of these tests read and
  // wrote the real settings location, which made them depend on the developer's
  // own preferences and quietly changed their theme.
  setUp(() {
    dir = Directory.systemTemp.createTempSync('settings_test');
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('defaults to following the system appearance', () async {
    final settings = await AppSettings.load(file: file);
    expect(settings.themeMode, ThemeMode.system);
  });

  test('round-trips a saved choice', () async {
    await (await AppSettings.load(file: file)).setThemeMode(ThemeMode.dark);
    final reloaded = await AppSettings.load(file: file);
    expect(reloaded.themeMode, ThemeMode.dark);
  });

  test('a corrupt file falls back instead of throwing', () async {
    file.writeAsStringSync('{ this is not json');
    final settings = await AppSettings.load(file: file);
    expect(settings.themeMode, ThemeMode.system);
  });

  test('an unknown mode name falls back', () async {
    file.writeAsStringSync('{"themeMode":"sepia"}');
    expect((await AppSettings.load(file: file)).themeMode, ThemeMode.system);
  });

  test('notifies exactly once per real change', () async {
    final settings = await AppSettings.load(file: file);
    var notifications = 0;
    settings.addListener(() => notifications++);

    await settings.setThemeMode(ThemeMode.dark);
    expect(notifications, 1);

    // Re-setting the same value must not rebuild the whole app for nothing.
    await settings.setThemeMode(ThemeMode.dark);
    expect(notifications, 1);

    await settings.setThemeMode(ThemeMode.light);
    expect(notifications, 2);
  });

  test('writes valid JSON naming the mode', () async {
    await (await AppSettings.load(file: file)).setThemeMode(ThemeMode.light);
    final decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<Map>());
    expect((decoded as Map)['themeMode'], 'light');
  });

  test('creates the directory if it does not exist', () async {
    final nested = File('${dir.path}/a/b/settings.json');
    await (await AppSettings.load(file: nested)).setThemeMode(ThemeMode.dark);
    expect(nested.existsSync(), isTrue);
  });
}
