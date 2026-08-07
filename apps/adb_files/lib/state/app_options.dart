/// Startup options passed on the command line.
///
/// A new window is a new *process* — Flutter has no stable multi-window
/// support — so anything a detached tab needs to carry over travels in argv.
/// The Swift side reads the geometry flags out of `CommandLine.arguments`
/// before the engine starts; Dart reads the rest here.
class AppOptions {
  const AppOptions({this.initialPath, this.adbPath, this.serial});

  /// Directory the first tab should open at. Null means the usual default.
  final String? initialPath;

  /// Path to the adb binary, handed down by the window that spawned this one.
  ///
  /// Finding adb costs ~220ms (a `which` plus a `start-server`, both process
  /// spawns). The parent already did that work and the daemon is provably
  /// running, so a detached window can skip straight past it.
  final String? adbPath;

  /// Device to attach to, so the child does not wait for device discovery.
  final String? serial;

  static const _pathFlag = '--path=';
  static const _adbFlag = '--adb=';
  static const _serialFlag = '--serial=';

  /// Flags understood by the native window code rather than by Dart. Listed
  /// here so the two sides cannot silently drift apart.
  static const geometryFlags = ['--width=', '--height=', '--x=', '--y='];

  static AppOptions parse(List<String> args) {
    String? read(String arg, String flag) {
      if (!arg.startsWith(flag)) return null;
      final value = arg.substring(flag.length);
      return value.isEmpty ? null : value;
    }

    String? path;
    String? adb;
    String? serial;
    for (final arg in args) {
      path ??= read(arg, _pathFlag);
      adb ??= read(arg, _adbFlag);
      serial ??= read(arg, _serialFlag);
    }
    return AppOptions(initialPath: path, adbPath: adb, serial: serial);
  }

  /// Builds the argument list for a detached window.
  ///
  /// Sizes are logical points, matching what the source window reports, so the
  /// new window comes up exactly the same size — which is the whole point of
  /// tearing a tab off rather than opening a fresh one.
  static List<String> buildArgs({
    required String path,
    required double width,
    required double height,
    double? x,
    double? y,
    String? adbPath,
    String? serial,
  }) => [
    '--path=$path',
    if (adbPath != null) '--adb=$adbPath',
    if (serial != null) '--serial=$serial',
    '--width=${width.round()}',
    '--height=${height.round()}',
    if (x != null) '--x=${x.round()}',
    if (y != null) '--y=${y.round()}',
  ];
}
