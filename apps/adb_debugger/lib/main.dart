import 'package:feature_connect/feature_connect.dart';
import 'package:flutter/material.dart';

import 'screens/console_screen.dart';
import 'theme.dart';

/// A live logcat and vitals console.
///
/// The second app on this stack, and the reason `feature_logcat` exists: it has
/// been built and tested since the beginning with nowhere to run. Composing it
/// is a pubspec entry plus a window, which is the architecture working as
/// intended.
void main() {
  runApp(const AdbDebuggerApp());
}

class AdbDebuggerApp extends StatefulWidget {
  const AdbDebuggerApp({super.key});

  @override
  State<AdbDebuggerApp> createState() => _AdbDebuggerAppState();
}

class _AdbDebuggerAppState extends State<AdbDebuggerApp> {
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
      title: 'ADB Debugger',
      debugShowCheckedModeBanner: false,
      theme: DebugTheme.of(Brightness.light),
      darkTheme: DebugTheme.of(Brightness.dark),
      // A log is read for long stretches, often beside an IDE that is already
      // dark. Following the system is right, but dark is the honest default
      // for what this is.
      themeMode: ThemeMode.dark,
      home: AnimatedBuilder(
        animation: _connection,
        builder: (context, _) {
          if (_connection.phase == ConnectionPhase.connected) {
            return ConsoleScreen(
              // Rebuild from scratch when the device changes, so no log or
              // sample from one device survives into another.
              key: ValueKey(_connection.device?.serial),
              connection: _connection,
            );
          }
          return Scaffold(body: ConnectPanel(controller: _connection));
        },
      ),
    );
  }
}
