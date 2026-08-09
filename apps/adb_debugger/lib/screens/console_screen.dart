import 'dart:async';

import 'package:adb_core/adb_core.dart';
import 'package:feature_connect/feature_connect.dart';
import 'package:feature_logcat/feature_logcat.dart';
import 'package:feature_stats/feature_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/log_toolbar.dart';
import '../widgets/status_bar.dart';
import '../widgets/vitals_rail.dart';

/// The window once a device is attached.
///
/// Layout follows what the tool is for: the log takes every pixel it can,
/// because that is what is being read, and vitals sit in a fixed rail beside it
/// so a CPU spike and the lines that caused it are visible at the same moment.
/// Nothing here is a tab — correlating the two is the entire point, and putting
/// them behind tabs would defeat it.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({required this.connection, super.key});

  final ConnectionController connection;

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  late final LogcatController _logs;
  late final StatsService _stats;

  StreamSubscription<DeviceStats>? _statsSub;
  DeviceStats? _latest;

  /// Recent overall-CPU readings, oldest first, for the sparkline.
  final List<double> _cpuHistory = [];
  static const _historyLength = 60;

  bool _railVisible = true;
  Object? _statsError;

  AdbSession get _session => widget.connection.session!;

  @override
  void initState() {
    super.initState();
    _logs = LogcatController(service: LogcatService(_session))
      ..addListener(_onLogs);
    _stats = StatsService(_session);

    // Capture starts immediately. A debugger that opens idle makes the user
    // press play before it is useful, and the interesting lines are usually
    // the ones already scrolling past.
    unawaited(_logs.start());
    _watchStats();
  }

  void _onLogs() {
    if (mounted) setState(() {});
  }

  void _watchStats() {
    _statsSub = _stats.watch().listen(
      (sample) {
        if (!mounted) return;
        setState(() {
          _latest = sample;
          _statsError = null;
          // `overall` is null on the very first sample — there is no previous
          // /proc/stat reading to diff against — so the history starts one
          // tick late rather than with a fabricated zero.
          if (sample.cpu.overall case final cpu?) {
            _cpuHistory.add(cpu);
            if (_cpuHistory.length > _historyLength) _cpuHistory.removeAt(0);
          }
        });
      },
      // A stats failure must never take the log down with it: the log is the
      // reason the window is open, and /proc parsing is the fragile half.
      onError: (Object e) {
        if (mounted) setState(() => _statsError = e);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_statsSub?.cancel());
    _logs
      ..removeListener(_onLogs)
      ..dispose();
    super.dispose();
  }

  Future<void> _copySelection() async {
    final text = _logs.visible.map((e) => e.raw).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('Copied ${_logs.visible.length} lines');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (!meta) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyK:
        // Cmd-K clears, as in every terminal.
        _logs.clearLocal();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _logs.setPaused(!_logs.isPaused);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyC:
        unawaited(_copySelection());
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Column(
          children: [
            LogToolbar(
              controller: _logs,
              deviceName: widget.connection.device?.displayName ?? 'Device',
              encrypted: widget.connection.isSessionEncrypted,
              railVisible: _railVisible,
              onToggleRail: () =>
                  setState(() => _railVisible = !_railVisible),
              onCopy: () => unawaited(_copySelection()),
              onDisconnect: widget.connection.disconnect,
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: LogcatView(controller: _logs)),
                  if (_railVisible) ...[
                    const VerticalDivider(width: 1),
                    VitalsRail(stats: _latest, cpuHistory: _cpuHistory,
                        error: _statsError),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ConsoleStatusBar(controller: _logs, stats: _latest),
          ],
        ),
      ),
    );
  }
}
