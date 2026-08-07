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

  /// Tail of the write queue. See [_save].
  Future<void> _pending = Future.value();

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

  /// Queues a write behind any already in flight.
  ///
  /// The UI calls [setThemeMode] without awaiting it, so a user toggling the
  /// appearance twice in quick succession would otherwise have two
  /// `writeAsString` calls racing on one path — which can interleave into
  /// invalid JSON, and the next launch would silently fall back to defaults.
  Future<void> _save() {
    return _pending = _pending.then((_) => _write());
  }

  /// Completes once every queued write has landed.
  ///
  /// Mainly for tests: on Windows a directory containing a file with an open
  /// handle cannot be deleted, so a test that taps the theme picker and then
  /// removes its temp directory fails unless it waits for the write. POSIX
  /// allows that delete, which is why it only ever broke on Windows CI.
  Future<void> flush() => _pending;

  Future<void> _write() async {
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
