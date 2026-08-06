import 'package:adb_ui/adb_ui.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/material.dart';

/// A place worth a one-click shortcut.
class Shortcut {
  const Shortcut(this.label, this.path, this.icon);

  final String label;
  final String path;
  final IconData icon;

  /// Ordered by how often someone actually wants them. DCIM and Download are
  /// the reason most people plug a phone into a Mac at all, so they come
  /// first, above the storage root.
  static const all = [
    Shortcut('Camera', '/sdcard/DCIM/Camera', Icons.photo_camera),
    Shortcut('Downloads', '/sdcard/Download', Icons.download),
    Shortcut('Pictures', '/sdcard/Pictures', Icons.image),
    Shortcut('Movies', '/sdcard/Movies', Icons.movie),
    Shortcut('Music', '/sdcard/Music', Icons.music_note),
    Shortcut('Documents', '/sdcard/Documents', Icons.description),
    Shortcut('Internal storage', '/sdcard', Icons.smartphone),
    Shortcut('Device root', '/', Icons.folder_special),
  ];
}

class Sidebar extends StatelessWidget {
  const Sidebar({
    required this.controller,
    required this.deviceName,
    this.freeSpace,
    super.key,
  });

  final FileBrowserController controller;
  final String deviceName;
  final ({int available, int total})? freeSpace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 208,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                Icon(Icons.smartphone, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    deviceName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final shortcut in Shortcut.all)
                  _SidebarItem(
                    shortcut: shortcut,
                    // Highlight the deepest matching shortcut, so browsing
                    // into DCIM/Camera/Foo still shows Camera as active
                    // rather than nothing.
                    selected: _activeShortcut?.path == shortcut.path,
                    onTap: () => controller.navigateTo(shortcut.path),
                  ),
              ],
            ),
          ),
          if (freeSpace != null) _FreeSpace(space: freeSpace!),
        ],
      ),
    );
  }

  Shortcut? get _activeShortcut {
    Shortcut? best;
    for (final shortcut in Shortcut.all) {
      if (!RemotePath.isWithin(shortcut.path, controller.path)) continue;
      if (best == null || shortcut.path.length > best.path.length) {
        best = shortcut;
      }
    }
    return best;
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.shortcut,
    required this.selected,
    required this.onTap,
  });

  final Shortcut shortcut;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(shortcut.icon, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shortcut.label,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeSpace extends StatelessWidget {
  const _FreeSpace({required this.space});

  final ({int available, int total}) space;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = space.total - space.available;
    final fraction = space.total == 0 ? 0.0 : used / space.total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Storage', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: fraction, minHeight: 5),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatBytes(space.available)} free',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
