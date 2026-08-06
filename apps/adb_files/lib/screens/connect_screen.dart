import 'package:adb_core/adb_core.dart';
import 'package:flutter/material.dart';

import '../state/connection_controller.dart';

/// Everything before a device is ready.
///
/// Each phase gets its own explanation and, where one exists, the actual fix —
/// a generic spinner or "connection failed" leaves the user with nothing to
/// act on.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({required this.controller, super.key});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) => switch (controller.phase) {
    ConnectionPhase.starting => const _Status(
      icon: Icons.hourglass_empty,
      title: 'Starting adb…',
      busy: true,
    ),
    ConnectionPhase.connecting => const _Status(
      icon: Icons.link,
      title: 'Connecting…',
      busy: true,
    ),
    ConnectionPhase.noAdbBinary => _NoAdb(controller: controller),
    ConnectionPhase.noDevice => _Status(
      icon: Icons.usb_off,
      title: 'No device connected',
      detail: 'Connect an Android device over USB and enable USB debugging in '
          'Developer options.\n\n'
          'If it is plugged in but not showing, check the cable — many USB '
          'cables carry power only and no data.',
      action: ('Retry', controller.retry),
    ),
    ConnectionPhase.unauthorized => _Status(
      icon: Icons.lock_outline,
      title: 'Waiting for authorization',
      detail: 'Look at your device: it is showing an "Allow USB debugging?" '
          'prompt. Tick "Always allow from this computer" and accept it.',
      busy: true,
    ),
    ConnectionPhase.choosing => _DevicePicker(controller: controller),
    ConnectionPhase.needsAddress => _AddressEntry(controller: controller),
    ConnectionPhase.awaitingDeviceAuthorization => _Status(
      icon: Icons.phonelink_lock,
      title: 'Allow this device',
      detail: 'Your Android device is showing an "Allow USB debugging?" '
          'prompt. Tick "Always allow from this computer" and accept it, then '
          'try again.\n\n'
          'The prompt only appears while the device is unlocked.',
      action: ('Try again', controller.resetToAddress),
    ),
    ConnectionPhase.failed => _Status(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      detail: '${controller.error}',
      action: ('Retry', controller.retry),
    ),
    ConnectionPhase.connected => const SizedBox.shrink(),
  };
}

class _NoAdb extends StatefulWidget {
  const _NoAdb({required this.controller});

  final ConnectionController controller;

  @override
  State<_NoAdb> createState() => _NoAdbState();
}

class _NoAdbState extends State<_NoAdb> {
  final _pathController = TextEditingController();
  bool _entering = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_entering) {
      return _Status(
        icon: Icons.extension_off,
        title: 'adb not found',
        detail: 'This app needs Android Platform Tools. Install them with '
            'Homebrew:\n\n'
            'brew install --cask android-platform-tools\n\n'
            'Or point the app at an existing adb binary.',
        action: ('Locate adb…', () => setState(() => _entering = true)),
        secondary: ('Retry', widget.controller.retry),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.folder_open, size: 48),
        const SizedBox(height: 16),
        Text(
          'Path to adb',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pathController,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '/opt/homebrew/bin/adb',
            isDense: true,
          ),
          onSubmitted: (v) => widget.controller.useAdbAt(v.trim()),
        ),
        if (widget.controller.error != null) ...[
          const SizedBox(height: 8),
          Text(
            '${widget.controller.error}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _entering = false),
              child: const Text('Back'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () =>
                  widget.controller.useAdbAt(_pathController.text.trim()),
              child: const Text('Use this'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Direct-wireless entry point. This is the whole iPad connect flow: there is
/// no adb server to discover, so the user supplies the device address.
class _AddressEntry extends StatefulWidget {
  const _AddressEntry({required this.controller});

  final ConnectionController controller;

  @override
  State<_AddressEntry> createState() => _AddressEntryState();
}

class _AddressEntryState extends State<_AddressEntry> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '5555');

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _connect() {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    widget.controller.connectDirect(
      host,
      port: int.tryParse(_port.text.trim()) ?? 5555,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.wifi_tethering, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Connect to a device',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the IP address shown in Developer options → Wireless '
          'debugging, or the address of a device you enabled with '
          '"adb tcpip 5555".',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'IP address',
                  hintText: '192.168.1.104',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _connect(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _connect(),
              ),
            ),
          ],
        ),
        if (widget.controller.error != null) ...[
          const SizedBox(height: 12),
          Text(
            '${widget.controller.error}',
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: _connect, child: const Text('Connect')),
        const SizedBox(height: 16),
        Text(
          'The device must be on the same network as this one. Some routers '
          'block devices from seeing each other — if the connection times out, '
          'check for "AP isolation" in your router settings.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.disabledColor,
          ),
        ),
      ],
    );
  }
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a device',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        for (final device in controller.devices)
          Card(
            child: ListTile(
              leading: Icon(
                device.kind == AdbConnectionKind.emulator
                    ? Icons.phone_android
                    : Icons.usb,
              ),
              title: Text(device.displayName),
              subtitle: Text(
                device.isOnline ? device.serial : _hint(device.state),
                style: device.isOnline
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              enabled: device.isOnline,
              onTap: device.isOnline
                  ? () => controller.connect(device)
                  : null,
            ),
          ),
      ],
    );
  }

  static String _hint(AdbDeviceState state) => switch (state) {
    AdbDeviceState.unauthorized => 'Accept the prompt on this device',
    AdbDeviceState.offline => 'Offline — reconnect the cable',
    _ => state.name,
  };
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    this.detail,
    this.busy = false,
    this.action,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final bool busy;
  final (String, VoidCallback)? action;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.titleLarge),
        if (detail != null) ...[
          const SizedBox(height: 12),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
        if (busy) ...[
          const SizedBox(height: 24),
          const SizedBox(
            width: 120,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        ],
        if (action != null || secondary != null) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (secondary != null)
                TextButton(
                  onPressed: secondary!.$2,
                  child: Text(secondary!.$1),
                ),
              if (action != null) ...[
                const SizedBox(width: 8),
                FilledButton(onPressed: action!.$2, child: Text(action!.$1)),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
