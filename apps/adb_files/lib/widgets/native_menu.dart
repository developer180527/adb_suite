import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the platform's own context menu where one exists.
///
/// On macOS this goes through a method channel to a real `NSMenu`, so the
/// metrics, vibrancy, highlight colour, keyboard handling, and dismissal all
/// come from AppKit. Flutter's `showMenu` is a Material popup that never quite
/// matches — and a file manager is exactly the kind of app where that stands
/// out.
///
/// Everywhere else it falls back to the Material menu, which is still correct,
/// just not native.
class NativeContextMenu {
  const NativeContextMenu._();

  static const _channel = MethodChannel('adb_files/context_menu');

  /// True where a real system menu is available.
  static bool get isSupported => Platform.isMacOS;

  /// Pops up a menu at [globalPosition] and returns the chosen action, or null
  /// if the user dismissed it.
  static Future<FileAction?> show({
    required BuildContext context,
    required Offset globalPosition,
    required List<FileAction?> items,
    required List<AdbFileEntry> selection,
  }) async {
    if (isSupported) {
      final chosen = await _showNative(globalPosition, items, selection);
      return chosen;
    }
    if (!context.mounted) return null;
    return _showMaterial(context, globalPosition, items, selection);
  }

  static Future<FileAction?> _showNative(
    Offset position,
    List<FileAction?> items,
    List<AdbFileEntry> selection,
  ) async {
    final payload = [
      for (final item in items)
        if (item == null)
          null
        else
          {
            'id': item.name,
            'label': item.label,
            // Disabled rather than omitted: a menu whose shape changes with
            // the selection is harder to build muscle memory for.
            'enabled': item.isEnabledFor(selection),
          },
    ];

    try {
      final id = await _channel.invokeMethod<String>('show', {
        'items': payload,
        'x': position.dx,
        'y': position.dy,
      });
      if (id == null) return null;
      return FileAction.values.firstWhere(
        (a) => a.name == id,
        orElse: () => FileAction.refresh,
      );
    } on PlatformException {
      // A channel failure should not swallow the interaction entirely.
      return null;
    } on MissingPluginException {
      // Running against a build whose runner predates the channel.
      return null;
    }
  }

  static Future<FileAction?> _showMaterial(
    BuildContext context,
    Offset position,
    List<FileAction?> items,
    List<AdbFileEntry> selection,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return Future.value();

    return showMenu<FileAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        for (final item in items)
          if (item == null)
            const PopupMenuDivider()
          else
            PopupMenuItem<FileAction>(
              value: item,
              enabled: item.isEnabledFor(selection),
              height: 32,
              child: Text(item.label, style: const TextStyle(fontSize: 13)),
            ),
      ],
    );
  }
}
