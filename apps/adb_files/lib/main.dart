import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/browser_screen.dart';
import 'theme.dart';
import 'screens/disconnected_screen.dart';
import 'state/app_options.dart';
import 'state/app_settings.dart';
import 'state/connection_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads libmpv. Measured at ~7ms, so it is not worth deferring.
  MediaKit.ensureInitialized();
  // pdfrx 2.x needs this before any PdfDocument is opened outside a widget.
  pdfrxFlutterInitialize();
  final settings = await AppSettings.load();
  runApp(AdbFilesApp(options: AppOptions.parse(args), settings: settings));
}

class AdbFilesApp extends StatefulWidget {
  const AdbFilesApp({
    required this.settings,
    this.options = const AppOptions(),
    super.key,
  });

  final AppOptions options;
  final AppSettings settings;

  @override
  State<AdbFilesApp> createState() => _AdbFilesAppState();
}

class _AdbFilesAppState extends State<AdbFilesApp> {
  late final _connection = ConnectionController(
    adbPath: widget.options.adbPath,
    preferredSerial: widget.options.serial,
  );

  @override
  void initState() {
    super.initState();
    _connection.initialise();
    // MaterialApp.themeMode is read at build time, so the whole app has to
    // rebuild when the preference changes.
    widget.settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() => setState(() {});

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Files',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(Brightness.light),
      darkTheme: AppTheme.of(Brightness.dark),
      themeMode: widget.settings.themeMode,
      home: AnimatedBuilder(
        animation: _connection,
        builder: (context, _) {
          // Keying on the serial rebuilds the browser from scratch when the
          // device changes, so no state leaks between devices.
          if (_connection.phase == ConnectionPhase.connected) {
            return BrowserScreen(
              key: ValueKey(_connection.device?.serial),
              connection: _connection,
              initialPath: widget.options.initialPath,
              settings: widget.settings,
            );
          }
          return DisconnectedScreen(controller: _connection);
        },
      ),
    );
  }
}
