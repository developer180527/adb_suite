import 'package:flutter/material.dart';

/// Chrome for an instrument, not a document.
///
/// Deliberately different from `adb_files`: a debugger is read at a glance
/// while something else is going on, often for hours, so density and a calm
/// surface matter more than comfort. Rows are tight, dividers are the only
/// decoration, and the accent is reserved for state that changes — never for
/// ornament.
class DebugTheme {
  const DebugTheme._();

  /// Amber rather than green, so this window is never mistaken for the file
  /// manager on a crowded desktop.
  static const _seed = Color(0xFFE8A33D);

  static ThemeData of(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
      // Material's defaults are sized for touch. Every control here sits in a
      // toolbar that must not steal height from the log.
      visualDensity: VisualDensity.compact,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
      // Explicit sizes: TextTheme.apply(fontSizeFactor:) asserts on Material
      // 2021 typography, which leaves some sizes null.
      textTheme: base.textTheme.copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 13),
      ),
    );
  }

  /// The font log output is read in.
  ///
  /// Alignment is the whole point: timestamps, PIDs and levels only scan as
  /// columns when the glyphs are the same width.
  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono', 'monospace'],
    fontSize: 12,
    height: 1.35,
  );
}
