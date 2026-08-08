import 'package:flutter/material.dart';

import '../state/connection_controller.dart';
import '../widgets/browser_toolbar.dart';
import '../widgets/sidebar.dart';
import 'connect_screen.dart';

/// The window with no device attached.
///
/// Shows the real chrome — sidebar, toolbar, tab strip, status bar — in an
/// inert state, with the connect flow filling the content area. A full-window
/// takeover made the app feel like it had not started yet; keeping the frame
/// present means connecting a phone changes what is *in* the window rather
/// than replacing it, and the window stops resizing its own layout under the
/// user when a cable is nudged.
///
/// Nothing here is a mock: [Sidebar] and [BrowserToolbar] are the same widgets
/// the live screen uses, handed nulls instead of a session, so the skeleton
/// cannot drift away from the real thing.
class DisconnectedScreen extends StatelessWidget {
  const DisconnectedScreen({required this.controller, super.key});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(deviceName: _deviceLabel),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const BrowserToolbar(),
                const Divider(height: 1),
                const _InertTabStrip(),
                Expanded(child: ConnectPanel(controller: controller)),
                _InertStatusBar(phase: controller.phase),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The sidebar header doubles as connection status, so it says what is
  /// happening rather than naming a device that is not there.
  String get _deviceLabel => switch (controller.phase) {
    ConnectionPhase.starting => 'Starting…',
    ConnectionPhase.connecting => 'Connecting…',
    ConnectionPhase.choosing => 'Choose a device',
    ConnectionPhase.unauthorized => 'Awaiting authorization',
    ConnectionPhase.awaitingDeviceAuthorization => 'Awaiting authorization',
    ConnectionPhase.noAdbBinary => 'adb not found',
    ConnectionPhase.failed => 'Not connected',
    _ => 'No device',
  };
}

/// A single placeholder tab, so the strip occupies its usual height.
///
/// The live tab bar hides itself when only one tab is open; this one is always
/// visible, because its whole job is to keep the skeleton the same shape as
/// the connected window.
class _InertTabStrip extends StatelessWidget {
  const _InertTabStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 110, maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
            child: Text(
              'No device',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.disabledColor,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'New Tab  ⌘T',
            visualDensity: VisualDensity.compact,
            onPressed: null,
          ),
        ],
      ),
    );
  }
}

class _InertStatusBar extends StatelessWidget {
  const _InertStatusBar({required this.phase});

  final ConnectionPhase phase;

  /// Phases where something is actively in flight and a progress hint belongs
  /// in the status bar.
  bool get _busy =>
      phase == ConnectionPhase.starting ||
      phase == ConnectionPhase.connecting ||
      phase == ConnectionPhase.unauthorized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'Not connected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.disabledColor,
            ),
          ),
          const Spacer(),
          if (_busy)
            const SizedBox(
              width: 60,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}
