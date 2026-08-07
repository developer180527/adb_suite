// Regenerates every platform's app icon from a single source image.
//
//   dart run tool/apply_icon.dart --source Assets/my-icon-1024.png
//   dart run tool/apply_icon.dart --source Assets/my-icon-1024.png \
//       --icon Assets/My-Icon.icon
//
// Only platforms that exist in the app are touched, so adding android/ or
// windows/ later needs no change here.
//
// Pure Dart on purpose: no ImageMagick, no sips, so it behaves the same on a
// developer machine and in CI.
import 'dart:io';

import 'package:image/image.dart' as img;

const _usage = '''
Regenerate app icons for every platform from one source image.

Usage:
  dart run tool/apply_icon.dart --source <png> [options]

Options:
  --source <png>   Square source image, 1024x1024 or larger. Required.
  --icon <path>    Icon Composer .icon bundle to use for macOS. Optional;
                   gives macOS the layered/dark-appearance icon instead of a
                   flattened PNG.
  --dark <png>     Dark-appearance variant for iOS 18+. Optional.
  --tinted <png>   Tinted-appearance variant for iOS 18+. Optional.
  --app <dir>      App directory to write into. Defaults to the current one.
  --dry-run        Report what would change without writing.
  -h, --help       Show this.
''';

Future<int> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    return 0;
  }

  final options = _Options.parse(args);
  if (options == null) {
    stderr.write(_usage);
    return 64; // EX_USAGE
  }

  final source = File(options.sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('Source not found: ${options.sourcePath}');
    return 66; // EX_NOINPUT
  }

  final decoded = img.decodeImage(await source.readAsBytes());
  if (decoded == null) {
    stderr.writeln('Could not decode ${options.sourcePath} as an image.');
    return 65; // EX_DATAERR
  }

  // Warn rather than fail: upscaling looks bad but is sometimes what you want
  // while iterating on a design.
  if (decoded.width != decoded.height) {
    stderr.writeln(
      'WARNING: source is ${decoded.width}x${decoded.height}, not square. '
      'Icons will be distorted.',
    );
  }
  if (decoded.width < 1024) {
    stderr.writeln(
      'WARNING: source is only ${decoded.width}px. 1024px or larger is '
      'recommended; smaller sources will look soft at large sizes.',
    );
  }

  stdout.writeln('Source : ${options.sourcePath} '
      '(${decoded.width}x${decoded.height})');
  stdout.writeln('App    : ${options.appDir}');
  if (options.dryRun) stdout.writeln('Mode   : dry run, nothing will be written');
  stdout.writeln('');

  final generators = <_Platform>[
    _MacOsPlatform(),
    _IosPlatform(),
    _AndroidPlatform(),
    _WebPlatform(),
    _WindowsPlatform(),
    _LinuxPlatform(),
  ];

  var wrote = 0;
  var skipped = 0;
  for (final platform in generators) {
    final root = Directory('${options.appDir}/${platform.directory}');
    if (!root.existsSync()) {
      stdout.writeln('${platform.name.padRight(8)} skipped (no '
          '${platform.directory}/)');
      skipped++;
      continue;
    }
    try {
      final count = await platform.generate(decoded, options);
      stdout.writeln('${platform.name.padRight(8)} $count file(s)');
      wrote += count;
    } on Object catch (e) {
      stderr.writeln('${platform.name.padRight(8)} FAILED: $e');
      return 70; // EX_SOFTWARE
    }
  }

  if (options.iconBundlePath != null) {
    final result = _checkIconComposer(options);
    stdout.writeln('');
    stdout.writeln(result);
  }

  stdout.writeln('');
  stdout.writeln('Done: $wrote file(s) '
      '${options.dryRun ? "would be written" : "written"}, '
      '$skipped platform(s) absent.');
  if (!options.dryRun) {
    stdout.writeln('Rebuild to see the change. macOS caches icons '
        'aggressively -- `killall Dock` if the old one lingers.');
  }
  return 0;
}

class _Options {
  _Options({
    required this.sourcePath,
    required this.appDir,
    required this.iconBundlePath,
    required this.darkPath,
    required this.tintedPath,
    required this.dryRun,
  });

  final String sourcePath;
  final String appDir;
  final String? iconBundlePath;
  final String? darkPath;
  final String? tintedPath;
  final bool dryRun;

  static _Options? parse(List<String> args) {
    String? source;
    String? icon;
    String? dark;
    String? tinted;
    var app = '.';
    var dryRun = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--source':
          if (++i >= args.length) return null;
          source = args[i];
        case '--icon':
          if (++i >= args.length) return null;
          icon = args[i];
        case '--dark':
          if (++i >= args.length) return null;
          dark = args[i];
        case '--tinted':
          if (++i >= args.length) return null;
          tinted = args[i];
        case '--app':
          if (++i >= args.length) return null;
          app = args[i];
        case '--dry-run':
          dryRun = true;
        default:
          if (args[i].startsWith('--source=')) {
            source = args[i].substring('--source='.length);
          } else if (args[i].startsWith('--icon=')) {
            icon = args[i].substring('--icon='.length);
          } else if (args[i].startsWith('--dark=')) {
            dark = args[i].substring('--dark='.length);
          } else if (args[i].startsWith('--tinted=')) {
            tinted = args[i].substring('--tinted='.length);
          } else if (args[i].startsWith('--app=')) {
            app = args[i].substring('--app='.length);
          } else {
            return null;
          }
      }
    }

    if (source == null) return null;
    return _Options(
      sourcePath: source,
      appDir: app,
      iconBundlePath: icon,
      darkPath: dark,
      tintedPath: tinted,
      dryRun: dryRun,
    );
  }
}

/// Reports whether the Xcode project is actually pointed at the .icon bundle.
///
/// Deliberately does not edit project.pbxproj: wiring a new file into an Xcode
/// project is a one-time operation, and silently rewriting the project on
/// every icon tweak is a good way to corrupt it.
String _checkIconComposer(_Options options) {
  final bundle = Directory(options.iconBundlePath!);
  if (!bundle.existsSync()) {
    return 'macOS .icon: NOT FOUND at ${options.iconBundlePath}';
  }

  final name = bundle.path.split('/').last.replaceAll('.icon', '');
  final project = File('${options.appDir}/macos/Runner.xcodeproj/project.pbxproj');
  if (!project.existsSync()) return 'macOS .icon: no Xcode project to check';

  final text = project.readAsStringSync();
  final wired = text.contains('ASSETCATALOG_COMPILER_APPICON_NAME = "$name"') ||
      text.contains('ASSETCATALOG_COMPILER_APPICON_NAME = $name;');
  final referenced = text.contains('$name.icon');

  if (wired && referenced) {
    return 'macOS .icon: "$name" is wired up; its layers drive the macOS icon '
        '(the generated PNGs act as a fallback).';
  }
  return 'macOS .icon: "$name" exists but the Xcode project does not use it.\n'
      '  Add it in Xcode (drag into Runner, then General > App Icons), or set\n'
      '  ASSETCATALOG_COMPILER_APPICON_NAME = "$name" and add it to the\n'
      '  Resources build phase.';
}

/// One platform's icon layout.
abstract class _Platform {
  String get name;
  String get directory;

  Future<int> generate(img.Image source, _Options options);

  /// Resizes with a good filter and writes a PNG.
  ///
  /// [opaque] produces a full-bleed image with no alpha. iOS and Android
  /// launcher icons must be full-bleed because the OS applies its own corner
  /// mask; macOS keeps alpha, because there the rounded corners *are* the
  /// artwork.
  Future<void> writePng(
    img.Image source,
    int size,
    File target, {
    required bool opaque,
    required bool dryRun,
  }) async {
    if (dryRun) return;
    // Fill the corners at full resolution before downscaling, so the seam is
    // resampled along with everything else instead of after.
    final prepared = opaque ? _fullBleed(source) : source;
    final resized = img.copyResize(
      prepared,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(img.encodePng(resized));
  }
}

/// Memoised per source image, so downscaling to a dozen sizes does not redo
/// the work. Keyed on identity rather than dimensions: the dark and tinted
/// variants are also 1024 square, and a size-keyed cache would hand back the
/// wrong artwork for them.
img.Image? _fullBleedSource;
img.Image? _fullBleedCache;

/// Extends the artwork into transparent corners so the result is full-bleed.
///
/// Icon Composer exports iOS icons already masked to a squircle, with the
/// corners transparent. iOS then applies its *own* mask, so anything put in
/// those corners can peek out around the edge of the system mask — flattening
/// them onto white produces a visible white halo on the Home Screen.
///
/// Rather than inventing a colour, the corners are filled with the icon's own
/// artwork: a slightly enlarged copy is placed underneath, so each corner
/// picks up the gradient that was already next to it. The original is then
/// composited on top unchanged, so nothing about the visible design moves.
img.Image _fullBleed(img.Image source) {
  final cached = _fullBleedCache;
  if (cached != null && identical(_fullBleedSource, source)) return cached;
  _fullBleedSource = source;

  final size = source.width;
  // 1.45 is enough that the crop's corners come from well inside the opaque
  // region: at 1024 they sample around (146,146), which is solid artwork.
  const zoom = 1.45;
  final enlarged = img.copyResize(
    source,
    width: (size * zoom).round(),
    height: (size * zoom).round(),
    interpolation: img.Interpolation.cubic,
  );
  final inset = ((enlarged.width - size) / 2).round();
  final backdrop = img.copyCrop(
    enlarged,
    x: inset,
    y: inset,
    width: size,
    height: size,
  );

  // White underneath is a last-resort floor; the backdrop should cover it
  // entirely for any icon whose edges are opaque.
  final canvas = img.Image(width: size, height: size, numChannels: 3)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, backdrop);
  img.compositeImage(canvas, source);

  return _fullBleedCache = canvas;
}

class _MacOsPlatform extends _Platform {
  @override
  String get name => 'macOS';
  @override
  String get directory => 'macos';

  // The sizes Flutter's default AppIcon.appiconset references.
  static const _sizes = [16, 32, 64, 128, 256, 512, 1024];

  @override
  Future<int> generate(img.Image source, _Options options) async {
    final dir = Directory(
      '${options.appDir}/macos/Runner/Assets.xcassets/AppIcon.appiconset',
    );
    if (!dir.existsSync()) return 0;

    for (final size in _sizes) {
      await writePng(
        source,
        size,
        File('${dir.path}/app_icon_$size.png'),
        // Alpha kept: macOS icons are not square, they have rounded corners
        // baked into the artwork.
        opaque: false,
        dryRun: options.dryRun,
      );
    }
    return _sizes.length;
  }
}

class _IosPlatform extends _Platform {
  @override
  String get name => 'iOS';
  @override
  String get directory => 'ios';

  @override
  Future<int> generate(img.Image source, _Options options) async {
    final dir = Directory(
      '${options.appDir}/ios/Runner/Assets.xcassets/AppIcon.appiconset',
    );
    final contents = File('${dir.path}/Contents.json');
    if (!contents.existsSync()) return 0;

    // Drive the sizes off Contents.json rather than a hard-coded list, so the
    // set stays correct if Flutter's template changes.
    final entries = _parseContents(contents.readAsStringSync());
    for (final entry in entries) {
      await writePng(
        source,
        entry.pixels,
        File('${dir.path}/${entry.filename}'),
        // The App Store rejects icons with an alpha channel, and iOS masks
        // the corners itself.
        opaque: true,
        dryRun: options.dryRun,
      );
    }
    var count = entries.length;

    // iOS 18+ appearance variants. These are 1024 single-size entries
    // alongside the legacy set; the system picks one by appearance.
    final variants = <String, String?>{
      'dark': options.darkPath,
      'tinted': options.tintedPath,
    }..removeWhere((_, path) => path == null);

    if (variants.isNotEmpty) {
      for (final entry in variants.entries) {
        final image = img.decodeImage(File(entry.value!).readAsBytesSync());
        if (image == null) {
          throw StateError('Could not decode ${entry.value}');
        }
        await writePng(
          image,
          1024,
          File('${dir.path}/Icon-App-1024x1024@1x-${entry.key}.png'),
          // Dark and tinted variants are composited by the system over its
          // own backdrop, so they keep alpha unlike the light icon.
          opaque: false,
          dryRun: options.dryRun,
        );
        count++;
      }
      if (!options.dryRun) {
        _writeContentsWithAppearances(contents, variants.keys.toSet());
      }
    }

    return count;
  }

  /// Adds `appearances` entries for the variants that exist.
  ///
  /// Appended rather than replacing the file, so the legacy per-size images
  /// stay for iOS 17 and earlier while 18+ picks up the variants.
  void _writeContentsWithAppearances(File contents, Set<String> variants) {
    var json = contents.readAsStringSync();
    if (json.contains('"appearances"')) return; // already present

    final additions = <String>[
      for (final variant in variants)
        '''
    {
      "size" : "1024x1024",
      "idiom" : "universal",
      "filename" : "Icon-App-1024x1024@1x-$variant.png",
      "scale" : "1x",
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "$variant"
        }
      ]
    }''',
    ];

    // Splice before the closing bracket of the "images" array.
    final close = json.lastIndexOf('],');
    if (close < 0) return;
    json = '${json.substring(0, close).trimRight()},\n'
        '${additions.join(',\n')}\n  ${json.substring(close)}';
    contents.writeAsStringSync(json);
  }
}

/// A filename plus the pixel size it needs to be.
class _IconEntry {
  const _IconEntry(this.filename, this.pixels);
  final String filename;
  final int pixels;
}

/// Minimal reader for an .appiconset Contents.json.
///
/// Hand-rolled rather than using dart:convert plus a model, because all that
/// is needed is (filename, size x scale) and the file is machine-generated.
List<_IconEntry> _parseContents(String json) {
  final entries = <_IconEntry>[];
  final blocks = json.split('{').skip(1);
  for (final block in blocks) {
    final filename = RegExp(r'"filename"\s*:\s*"([^"]+)"').firstMatch(block);
    final size = RegExp(r'"size"\s*:\s*"([\d.]+)x').firstMatch(block);
    final scale = RegExp(r'"scale"\s*:\s*"(\d+)x"').firstMatch(block);
    if (filename == null || size == null || scale == null) continue;
    final pixels =
        (double.parse(size.group(1)!) * int.parse(scale.group(1)!)).round();
    entries.add(_IconEntry(filename.group(1)!, pixels));
  }
  return entries;
}

class _AndroidPlatform extends _Platform {
  @override
  String get name => 'Android';
  @override
  String get directory => 'android';

  /// Launcher icon sizes per density bucket.
  static const _densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  @override
  Future<int> generate(img.Image source, _Options options) async {
    final res = Directory('${options.appDir}/android/app/src/main/res');
    if (!res.existsSync()) return 0;

    var count = 0;
    for (final entry in _densities.entries) {
      await writePng(
        source,
        entry.value,
        File('${res.path}/mipmap-${entry.key}/ic_launcher.png'),
        // Android launcher icons are composited by the launcher; opaque
        // avoids odd halos on legacy (pre-adaptive) launchers.
        opaque: true,
        dryRun: options.dryRun,
      );
      count++;
    }
    return count;
  }
}

class _WebPlatform extends _Platform {
  @override
  String get name => 'Web';
  @override
  String get directory => 'web';

  @override
  Future<int> generate(img.Image source, _Options options) async {
    final web = Directory('${options.appDir}/web');
    if (!web.existsSync()) return 0;

    final targets = {
      'icons/Icon-192.png': 192,
      'icons/Icon-512.png': 512,
      'icons/Icon-maskable-192.png': 192,
      'icons/Icon-maskable-512.png': 512,
      'favicon.png': 32,
    };
    for (final entry in targets.entries) {
      await writePng(
        source,
        entry.value,
        File('${web.path}/${entry.key}'),
        opaque: false,
        dryRun: options.dryRun,
      );
    }
    return targets.length;
  }
}

class _WindowsPlatform extends _Platform {
  @override
  String get name => 'Windows';
  @override
  String get directory => 'windows';

  /// Sizes Windows expects inside a single .ico.
  static const _sizes = [16, 24, 32, 48, 64, 128, 256];

  @override
  Future<int> generate(img.Image source, _Options options) async {
    final target =
        File('${options.appDir}/windows/runner/resources/app_icon.ico');
    if (!target.parent.existsSync()) return 0;
    if (options.dryRun) return 1;

    // A .ico is a container of several sizes; Explorer picks per context.
    final frames = [
      for (final size in _sizes)
        img.copyResize(
          source,
          width: size,
          height: size,
          interpolation: img.Interpolation.cubic,
        ),
    ];
    await target.writeAsBytes(img.IcoEncoder().encodeImages(frames));
    return 1;
  }
}

class _LinuxPlatform extends _Platform {
  @override
  String get name => 'Linux';
  @override
  String get directory => 'linux';

  /// Sizes the freedesktop hicolor theme expects.
  static const _sizes = [16, 24, 32, 48, 64, 128, 256, 512];

  @override
  Future<int> generate(img.Image source, _Options options) async {
    final linux = Directory('${options.appDir}/linux');
    if (!linux.existsSync()) return 0;

    // Linux has no in-runner icon slot the way Windows and macOS do. Desktop
    // environments read icons out of the hicolor theme, matched by the `Icon=`
    // name in a .desktop file, so that is what gets generated here. The
    // packaging step installs both into the system (or ~/.local/share).
    final appName = _appName(options.appDir);

    for (final size in _sizes) {
      await writePng(
        source,
        size,
        File('${linux.path}/icons/hicolor/${size}x$size/apps/$appName.png'),
        // Alpha kept: Linux desktops composite icons over a panel or dock
        // background rather than masking them to a fixed shape.
        opaque: false,
        dryRun: options.dryRun,
      );
    }

    // Written once and then left alone, so hand edits (categories, keywords,
    // translations) survive later icon runs.
    final desktop = File('${linux.path}/$appName.desktop');
    final createdDesktop = !desktop.existsSync();
    if (!options.dryRun && createdDesktop) {
      desktop.writeAsStringSync(_desktopEntry(appName));
    }

    return _sizes.length + (createdDesktop ? 1 : 0);
  }

  /// Derives the binary and icon name from the app directory.
  static String _appName(String appDir) {
    final normalized = appDir.endsWith('/')
        ? appDir.substring(0, appDir.length - 1)
        : appDir;
    final last = normalized.split('/').last;
    return (last.isEmpty || last == '.')
        ? Directory.current.path.split('/').last
        : last;
  }

  static String _desktopEntry(String appName) => [
    '[Desktop Entry]',
    'Type=Application',
    'Name=Files',
    'GenericName=Android File Manager',
    'Comment=Browse and transfer files on an Android device over ADB',
    'Exec=$appName',
    'Icon=$appName',
    'Terminal=false',
    'Categories=Utility;FileTools;',
    'Keywords=android;adb;files;transfer;',
    '',
  ].join('\n');
}
