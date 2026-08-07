/// Startup options passed on the command line.
///
/// A new window is a new *process* — Flutter has no stable multi-window
/// support — so anything a detached tab needs to carry over travels in argv.
/// The Swift side reads the geometry flags out of `CommandLine.arguments`
/// before the engine starts; Dart reads the rest here.
class AppOptions {
  const AppOptions({this.initialPath});

  /// Directory the first tab should open at. Null means the usual default.
  final String? initialPath;

  static const _pathFlag = '--path=';

  /// Flags understood by the native window code rather than by Dart. Listed
  /// here so the two sides cannot silently drift apart.
  static const geometryFlags = ['--width=', '--height=', '--x=', '--y='];

  static AppOptions parse(List<String> args) {
    String? path;
    for (final arg in args) {
      if (arg.startsWith(_pathFlag)) {
        final value = arg.substring(_pathFlag.length);
        if (value.isNotEmpty) path = value;
      }
    }
    return AppOptions(initialPath: path);
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
  }) => [
    '--path=$path',
    '--width=${width.round()}',
    '--height=${height.round()}',
    if (x != null) '--x=${x.round()}',
    if (y != null) '--y=${y.round()}',
  ];
}
