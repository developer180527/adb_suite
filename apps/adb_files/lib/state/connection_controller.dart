import 'dart:async';
import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/foundation.dart';

/// Where the app is in the connect flow.
///
/// Each of these needs a different message and a different suggested action.
/// Collapsing them into a generic "could not connect" is the difference
/// between a user fixing the problem in ten seconds and giving up.
enum ConnectionPhase {
  /// Looking for the adb binary and starting the daemon.
  starting,

  /// No `adb` executable anywhere we know to look.
  noAdbBinary,

  /// adb is running, but no device is plugged in.
  noDevice,

  /// A device is visible but has not accepted the RSA prompt.
  unauthorized,

  /// Devices are available; waiting for the user to pick one.
  choosing,

  /// No local adb is possible (iOS), so the user must type a device address.
  needsAddress,

  /// The device was shown our public key; waiting for the on-device dialog.
  awaitingDeviceAuthorization,

  /// Opening a session with the chosen device.
  connecting,

  /// Ready.
  connected,

  /// Something else went wrong.
  failed,
}

class ConnectionController extends ChangeNotifier {
  ConnectionController({this.adbPath, this.preferredSerial});

  /// Supplied by the window that spawned this one, to skip discovery.
  final String? adbPath;
  final String? preferredSerial;

  ConnectionPhase _phase = ConnectionPhase.starting;
  HostTransport? _transport;
  AdbSession? _session;
  FileService? _fileService;
  TransferManager? _transfers;
  StreamSubscription<List<AdbDevice>>? _deviceSub;

  List<AdbDevice> _devices = const [];
  Object? _error;

  ConnectionPhase get phase => _phase;
  List<AdbDevice> get devices => _devices;
  Object? get error => _error;
  AdbSession? get session => _session;
  FileService? get fileService => _fileService;
  TransferManager? get transfers => _transfers;
  HostTransport? get transport => _transport;
  AdbDevice? get device => _session?.device;

  /// True when this platform can host a local adb daemon.
  ///
  /// iOS cannot: it forbids spawning processes, so there is no `adb` binary to
  /// start and no local server to talk to. The direct-wireless transport needs
  /// only a socket, which is why iPad works at all.
  static bool get supportsLocalServer =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  /// Locates adb, starts the daemon, and begins watching for devices.
  Future<void> initialise() async {
    if (!supportsLocalServer) {
      _set(ConnectionPhase.needsAddress);
      return;
    }

    _set(ConnectionPhase.starting);

    try {
      final handedDown = adbPath;
      if (handedDown != null) {
        // A detached window reuses the parent's adb path instead of
        // searching again. Measured, this does *not* make startup faster --
        // the cost simply moves to the first daemon round trip. It is kept
        // because a GUI process launched via `open` does not inherit the
        // shell's PATH, so `which adb` can fail in the child even though the
        // parent found it. Handing the answer down removes that failure mode.
        _transport = HostTransport(binary: AdbBinary(handedDown));
      } else {
        _transport = await HostTransport.local();
      }
    } on AdbBinaryNotFound catch (e) {
      _error = e;
      _set(ConnectionPhase.noAdbBinary);
      return;
    } on Object catch (e) {
      _error = e;
      _set(ConnectionPhase.failed);
      return;
    }

    // Attach to the known device immediately rather than waiting for the
    // first track-devices push. The subscription below still starts, so
    // disconnects are noticed as usual.
    final serial = preferredSerial;
    if (serial != null) {
      unawaited(
        connect(AdbDevice(serial: serial, state: AdbDeviceState.device)),
      );
    }

    // trackDevices reconnects internally, so one subscription lasts the whole
    // session and survives the daemon being restarted underneath us.
    _deviceSub = _transport!.trackDevices().listen(
      _onDevices,
      onError: (Object e) {
        _error = e;
        _set(ConnectionPhase.failed);
      },
    );
  }

  /// Points at an adb binary the user picked by hand.
  Future<void> useAdbAt(String path) async {
    try {
      final binary = await AdbBinary.at(path);
      await binary.startServer();
      _transport = HostTransport(binary: binary);
      _error = null;
      await _deviceSub?.cancel();
      _deviceSub = _transport!.trackDevices().listen(_onDevices);
    } on Object catch (e) {
      _error = e;
      _set(ConnectionPhase.noAdbBinary);
    }
  }

  void _onDevices(List<AdbDevice> devices) {
    _devices = devices;

    // Never override an established session because the list churned.
    if (_session != null) {
      final stillThere =
          devices.any((d) => d.serial == _session!.device.serial && d.isOnline);
      if (!stillThere) {
        _teardownSession();
        _phase = devices.isEmpty
            ? ConnectionPhase.noDevice
            : ConnectionPhase.choosing;
      }
      notifyListeners();
      return;
    }

    final online = devices.where((d) => d.isOnline).toList();

    if (devices.isEmpty) {
      _phase = ConnectionPhase.noDevice;
    } else if (online.isEmpty) {
      // Everything visible is unauthorized or offline. Surfacing this rather
      // than "no device" is what tells the user to look at their phone.
      _phase = devices.any((d) => d.state == AdbDeviceState.unauthorized)
          ? ConnectionPhase.unauthorized
          : ConnectionPhase.noDevice;
    } else if (online.length == 1) {
      // Exactly one device is the overwhelmingly common case; skip the picker.
      unawaited(connect(online.single));
      return;
    } else {
      _phase = ConnectionPhase.choosing;
    }

    notifyListeners();
  }

  Future<void> connect(AdbDevice device) async {
    final transport = _transport;
    if (transport == null) return;

    _set(ConnectionPhase.connecting);
    try {
      final connection = await transport.connect(device.serial);
      final session = AdbSession(connection, device);
      final service = FileService(session);

      _session = session;
      _fileService = service;
      _transfers = TransferManager(service);
      _error = null;
      _set(ConnectionPhase.connected);
    } on Object catch (e) {
      _error = e;
      _set(ConnectionPhase.failed);
    }
  }

  // --- direct wireless (the iPad path) ---

  /// Where the RSA identity lives.
  ///
  /// Persisting it is what makes "Always allow from this computer" stick — a
  /// fresh key on every launch would re-prompt the user every time. On iOS,
  /// HOME is the app sandbox, so Documents survives restarts without pulling
  /// in a path_provider dependency.
  Future<File> get _keyFile async {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = Directory('$home/Documents');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/adb_identity.json');
  }

  Future<AdbAuthKey> _loadOrCreateKey() async {
    final file = await _keyFile;
    if (file.existsSync()) {
      try {
        return AdbAuthKey.decode(file.readAsStringSync());
      } on Object {
        // A corrupt key is not worth failing over; make a new one and accept
        // that the user re-authorises once.
      }
    }
    final key = AdbAuthKey.generate();
    file.writeAsStringSync(key.encode());
    return key;
  }

  /// Connects straight to a device's adbd over TCP, with no adb server.
  ///
  /// Requires `adb tcpip 5555` to have been run once over USB, or Wireless
  /// debugging enabled on Android 11+.
  Future<void> connectDirect(String host, {int port = 5555}) async {
    _set(ConnectionPhase.connecting);

    try {
      final key = await _loadOrCreateKey();
      final outcome = await DirectAdbConnection.connect(
        host: host,
        port: port,
        key: key,
        name: 'adb_files@${Platform.operatingSystem}',
      );

      switch (outcome.result) {
        case DirectConnectResult.connected:
          final connection = outcome.connection!;
          final device = AdbDevice(
            serial: '$host:$port',
            state: AdbDeviceState.device,
            model: _modelFromBanner(connection.banner),
          );
          final session = AdbSession(connection, device);
          final service = FileService(session);

          _session = session;
          _fileService = service;
          _transfers = TransferManager(service);
          _error = null;
          _set(ConnectionPhase.connected);

        case DirectConnectResult.awaitingAuthorization:
          _set(ConnectionPhase.awaitingDeviceAuthorization);

        case DirectConnectResult.rejected:
          _error = 'The device refused the connection. Check that '
              '"adb tcpip 5555" was run and the address is right.';
          _set(ConnectionPhase.failed);
      }
    } on SocketException catch (e) {
      // By far the most common failure, and almost never the app's fault:
      // wrong address, phone asleep, or the router isolating clients.
      _error = 'Could not reach $host:$port — ${e.osError?.message ?? e.message}';
      _set(ConnectionPhase.failed);
    } on Object catch (e) {
      _error = e;
      _set(ConnectionPhase.failed);
    }
  }

  static String? _modelFromBanner(String banner) {
    for (final part in banner.split(';')) {
      if (part.startsWith('ro.product.model=')) {
        return part.substring('ro.product.model='.length);
      }
    }
    return null;
  }

  /// Back to the address entry screen.
  void resetToAddress() {
    _teardownSession();
    _set(ConnectionPhase.needsAddress);
  }

  /// Returns to the device picker without tearing down the transport.
  void disconnect() {
    if (!supportsLocalServer) {
      resetToAddress();
      return;
    }
    _teardownSession();
    _phase = _devices.where((d) => d.isOnline).isEmpty
        ? ConnectionPhase.noDevice
        : ConnectionPhase.choosing;
    notifyListeners();
  }

  Future<void> retry() async {
    if (!supportsLocalServer) {
      resetToAddress();
      return;
    }
    _teardownSession();
    await _deviceSub?.cancel();
    _deviceSub = null;
    await _transport?.close();
    _transport = null;
    _error = null;
    await initialise();
  }

  void _teardownSession() {
    _transfers?.cancelAll();
    _transfers?.dispose();
    _transfers = null;
    _fileService = null;
    unawaited(_session?.close());
    _session = null;
  }

  void _set(ConnectionPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _teardownSession();
    _transport?.close();
    super.dispose();
  }
}
