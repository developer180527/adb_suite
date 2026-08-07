import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// User preferences, persisted to a small JSON file.
///
/// A file rather than `shared_preferences`: the app already writes JSON to
/// disk for the ADB identity, and this avoids a plugin dependency that would
/// then need wiring on five platforms.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._file, this._themeMode);

  final File _file;
  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  /// Loads settings, falling back to defaults if anything is missing or
  /// corrupt — preferences are never worth failing startup over.
  ///
  /// [file] overrides the location, so tests can exercise this without
  /// touching (or depending on) the real user's preferences.
  static Future<AppSettings> load({File? file}) async {
    file ??= _settingsFile();
    var mode = ThemeMode.system;
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map && decoded['themeMode'] is String) {
          mode = ThemeMode.values.firstWhere(
            (m) => m.name == decoded['themeMode'],
            orElse: () => ThemeMode.system,
          );
        }
      }
    } on Object {
      // Corrupt file: start clean rather than refusing to launch.
    }
    return AppSettings._(file, mode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      _file.parent.createSync(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'themeMode': _themeMode.name,
        }),
      );
    } on Object {
      // Failing to persist a preference should not surface as an error; the
      // choice still applies for this session.
    }
  }

  /// Application Support on desktop, the app container on iOS.
  static File _settingsFile() {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    if (Platform.isMacOS || Platform.isIOS) {
      return File('$home/Library/Application Support/com.adbsuite.adbFiles/'
          'settings.json');
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? home;
      return File('$appData/adb_files/settings.json');
    }
    // Linux and anything else: the XDG default.
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    return File('$config/adb_files/settings.json');
  }
}
