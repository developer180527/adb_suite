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
  Widget build(BuildContext context) =>
      Scaffold(body: ConnectPanel(controller: controller));
}

/// The connect flow with no window chrome of its own, so it can sit inside the
/// disconnected skeleton's content area as well as fill a bare screen.
class ConnectPanel extends StatelessWidget {
  const ConnectPanel({required this.controller, super.key});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
      secondary: controller.supportsWirelessPairing
          ? ('Connect over Wi-Fi…', () => showWirelessDialog(context, controller))
          : null,
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
      secondary: controller.supportsWirelessPairing
          ? ('Connect over Wi-Fi…', () => showWirelessDialog(context, controller))
          : null,
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

  /// Deliberately blank. The Wireless debugging port is assigned afresh every
  /// time the setting is toggled, so any prefilled value is wrong more often
  /// than it is right.
  final _port = TextEditingController();

  String? _validation;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _connect() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());

    if (host.isEmpty) {
      setState(() => _validation = 'Enter the device\'s IP address.');
      return;
    }
    // Never fall back to 5555 for a missing port. That silently swaps an
    // encrypted connection for a plaintext one, which is the opposite of what
    // someone reading "encrypted" on this screen has agreed to.
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _validation =
            'Enter the port from Developer options → Wireless debugging.';
      });
      return;
    }

    setState(() => _validation = null);
    widget.controller.connectDirect(host, port: port);
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
          'On the device: Developer options → Wireless debugging. Enter the '
          'IP address and port shown there.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'That connection is encrypted.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The port changes every time wireless debugging is switched off and '
          'on, so check it each time rather than reusing an old one.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.disabledColor,
          ),
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
                  hintText: '37115',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _connect(),
              ),
            ),
          ],
        ),
        if (_validation != null) ...[
          const SizedBox(height: 10),
          Text(
            _validation!,
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
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
        const SizedBox(height: 20),
        // The one thing the Wireless debugging screen cannot do for you.
        // Android's pairing code exchange needs a desktop adb server, so the
        // device is taught to trust this app over the legacy port instead —
        // once — and every connection after that is encrypted.
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            'First time with this device?',
            style: theme.textTheme.bodySmall,
          ),
          children: [
            Text(
              'The device has to be told to trust this app once, and the '
              'pairing code on the Wireless debugging screen cannot do it — '
              'that exchange needs a desktop adb server.\n\n'
              'From a computer with the device connected over USB:\n'
              '    adb tcpip 5555\n\n'
              'Connect here to port 5555 and accept the prompt on the device. '
              'Then run "adb usb" to close that unencrypted port again. From '
              'then on, use the Wireless debugging port above and the '
              'connection is encrypted.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'The device must be reachable from this one. Many routers block '
          'devices from seeing each other — if the connection times out, look '
          'for "AP isolation" in the router settings, or put both devices on a '
          'VPN such as Tailscale.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.disabledColor,
          ),
        ),
      ],
    );
  }
}

/// Opens the Wi-Fi connect/pair sheet.
Future<void> showWirelessDialog(
  BuildContext context,
  ConnectionController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => WirelessDialog(controller: controller),
);

/// Connect-over-Wi-Fi for desktop, where a local adb server exists.
///
/// Two steps, because Android splits them: pairing is a one-time trust
/// exchange on a port that changes every time the pairing dialog is opened,
/// and connecting uses a *different*, stable port. Conflating them is the
/// single most common reason wireless debugging appears not to work, so they
/// are separate panels here with the port difference spelled out.
///
/// Devices set up the old way (`adb tcpip 5555` over USB) skip pairing
/// entirely, which is why Connect is the default panel.
class WirelessDialog extends StatefulWidget {
  const WirelessDialog({required this.controller, super.key});

  final ConnectionController controller;

  @override
  State<WirelessDialog> createState() => _WirelessDialogState();
}

class _WirelessDialogState extends State<WirelessDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '5555');
  final _pairHost = TextEditingController();
  final _pairPort = TextEditingController();
  final _code = TextEditingController();

  bool _pairing = false;
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pairHost.dispose();
    _pairPort.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    if (host.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    await widget.controller.connectWireless(
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 5555,
    );

    if (!mounted) return;
    // The controller owns the outcome: it has either moved to `connected` or
    // recorded why not. Reading it back keeps one source of truth rather than
    // duplicating the success rules here.
    if (widget.controller.phase == ConnectionPhase.connected) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _failed = true;
      _message = '${widget.controller.error}';
    });
  }

  Future<void> _pair() async {
    final host = _pairHost.text.trim();
    final port = int.tryParse(_pairPort.text.trim());
    final code = _code.text.trim();
    if (host.isEmpty || port == null || code.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final reply = await widget.controller.pairWireless(
        host: host,
        port: port,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = false;
        _message = reply.trim();
        // Pairing tells us the device's address; carry it over so the user
        // does not retype it, but not the port — the connect port is not the
        // pairing port.
        if (_host.text.trim().isEmpty) _host.text = host;
        _pairing = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _message = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_pairing ? 'Pair a device' : 'Connect over Wi-Fi'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _pairing
                  ? 'On the device: Developer options → Wireless debugging → '
                        '"Pair device with pairing code". Use the address, port '
                        'and code from that dialog — its port is only for '
                        'pairing and changes each time.'
                  : 'On the device: Developer options → Wireless debugging. '
                        'Use the address and port shown on that screen (not the '
                        'pairing dialog). Devices set up with "adb tcpip 5555" '
                        'use port 5555.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_pairing) ...[
              _AddressRow(
                host: _pairHost,
                port: _pairPort,
                portLabel: 'Pairing port',
                portHint: '37115',
                onSubmit: _pair,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _code,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  hintText: '123456',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _pair(),
              ),
            ] else
              _AddressRow(
                host: _host,
                port: _port,
                portLabel: 'Port',
                portHint: '5555',
                autofocus: true,
                onSubmit: _connect,
              ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
      // No Spacer here: AlertDialog lays its actions out in an OverflowBar,
      // which is not a Flex, so a Spacer asserts as soon as the dialog opens.
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _pairing = !_pairing;
                  _message = null;
                }),
          child: Text(_pairing ? 'Back' : 'Pair a new device…'),
        ),
        // Stays enabled while busy on purpose. A connection attempt can run
        // for the full timeout, and trapping the user in a dialog they cannot
        // dismiss for that long is worse than letting them leave: the attempt
        // finishes on the controller regardless, and a device that does answer
        // still lands them in the browser.
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : (_pairing ? _pair : _connect),
          child: Text(_pairing ? 'Pair' : 'Connect'),
        ),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.host,
    required this.port,
    required this.portLabel,
    required this.portHint,
    required this.onSubmit,
    this.autofocus = false,
  });

  final TextEditingController host;
  final TextEditingController port;
  final String portLabel;
  final String portHint;
  final VoidCallback onSubmit;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: host,
            autofocus: autofocus,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'IP address',
              hintText: '192.168.1.104',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 10),
        // Wide enough for "Pairing port" to render in full; at a narrower
        // flex the label truncates to "Pairing …", which hides the one word
        // that distinguishes this field from the connect port.
        Expanded(
          flex: 2,
          child: TextField(
            controller: port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: portLabel,
              hintText: portHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => onSubmit(),
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
        if (controller.supportsWirelessPairing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.wifi, size: 16),
            label: const Text('Connect over Wi-Fi…'),
            onPressed: () => showWirelessDialog(context, controller),
          ),
        ],
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
