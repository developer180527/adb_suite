import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/browser_screen.dart';
import 'screens/connect_screen.dart';
import 'state/app_options.dart';
import 'state/connection_controller.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads libmpv. Must run before any Player is constructed.
  MediaKit.ensureInitialized();
  runApp(AdbFilesApp(options: AppOptions.parse(args)));
}

class AdbFilesApp extends StatefulWidget {
  const AdbFilesApp({this.options = const AppOptions(), super.key});

  final AppOptions options;

  @override
  State<AdbFilesApp> createState() => _AdbFilesAppState();
}

class _AdbFilesAppState extends State<AdbFilesApp> {
  final _connection = ConnectionController();

  @override
  void initState() {
    super.initState();
    _connection.initialise();
  }

  @override
  void dispose() {
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Files',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
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
            );
          }
          return ConnectScreen(controller: _connection);
        },
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3DDC84), // Android green
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Desktop density: the default Material spacing wastes a lot of vertical
      // room in a file list.
      visualDensity: VisualDensity.compact,
      dividerTheme: const DividerThemeData(space: 1, thickness: 1),
    );
  }
}
