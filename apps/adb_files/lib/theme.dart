import 'package:flutter/material.dart';

/// The app's visual theme.
///
/// Deliberately restrained. Material's default `fromSeed` floods every surface
/// with tinted colour, which reads as an Android app on a Mac desktop and
/// fights the file content — thumbnails, document previews, and video frames
/// are the things that should carry colour here.
///
/// So: near-neutral greys for chrome, with the icon's green reserved for
/// selection, focus, and progress. Density is tight, because a file manager
/// lives or dies on how many rows fit on screen.
class AppTheme {
  const AppTheme._();

  /// From the app icon, so the accent and the icon agree.
  static const seed = Color(0xFF5CC85F);

  static ThemeData of(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        ).copyWith(
          // Pull the tint out of the large surfaces; keep it on the accents.
          surface: dark ? const Color(0xFF1C1C1E) : const Color(0xFFFCFCFC),
          surfaceContainerLow:
              dark ? const Color(0xFF232326) : const Color(0xFFF2F2F4),
          surfaceContainerHighest:
              dark ? const Color(0xFF2C2C30) : const Color(0xFFE8E8EC),
        );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // The default Material spacing wastes a lot of vertical room in a list.
      visualDensity: VisualDensity.compact,
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: dark ? const Color(0xFF3A3A3E) : const Color(0xFFDCDCE0),
      ),
      // Desktop text is smaller than Material's phone-oriented defaults.
      //
      // Sizes are set explicitly rather than via `apply(fontSizeFactor:)`:
      // that asserts every style already has a non-null fontSize, which is
      // not true of Material 2021 typography, and the failure is a full-screen
      // red error rather than a graceful fallback.
      textTheme: _textTheme(scheme),
      iconTheme: IconThemeData(size: 18, color: scheme.onSurfaceVariant),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(30, 30),
          padding: const EdgeInsets.all(5),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
        thumbVisibility: WidgetStateProperty.all(false),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF3A3A3E)
            : const Color(0xFF303034),
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Desktop-scale type. Only the styles the app actually uses are overridden;
  /// the rest inherit Material's defaults.
  static TextTheme _textTheme(ColorScheme scheme) {
    final on = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return TextTheme(
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: on,
      ),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: on),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on),
      bodyLarge: TextStyle(fontSize: 14, color: on),
      bodyMedium: TextStyle(fontSize: 13, color: on),
      bodySmall: TextStyle(fontSize: 12, color: muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on),
      labelMedium: TextStyle(fontSize: 12, color: muted),
      labelSmall: TextStyle(fontSize: 11, color: muted),
    );
  }
}
