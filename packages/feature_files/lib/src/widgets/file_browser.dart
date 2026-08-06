import 'package:adb_core/adb_core.dart';
import 'package:adb_ui/adb_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../file_browser_controller.dart';
import '../models/directory_listing.dart';
import '../models/file_action.dart';
import '../models/file_sort.dart';
import '../remote_path.dart';

/// Directory listing with breadcrumbs, sorting, selection, and context menus.
class FileBrowser extends StatelessWidget {
  const FileBrowser({
    required this.controller,
    this.onOpenFile,
    this.onAction,
    this.rowWrapper,
    this.showNavigationBar = true,
    super.key,
  });

  final FileBrowserController controller;
  final void Function(AdbFileEntry)? onOpenFile;

  /// Invoked for a context-menu choice with the entries it applies to.
  final void Function(FileAction, List<AdbFileEntry>)? onAction;

  /// Optional decorator around each row.
  ///
  /// Exists so an app can make rows draggable without this package taking on
  /// a drag-and-drop dependency — which matters because the usual one needs a
  /// Rust toolchain and has no place in an iPad build.
  final Widget Function(BuildContext, AdbFileEntry, Widget)? rowWrapper;

  /// Set false when the host app supplies its own navigation controls and
  /// places [FileBreadcrumbs] elsewhere — a Finder-style path bar along the
  /// bottom, for instance.
  final bool showNavigationBar;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        children: [
          if (showNavigationBar) ...[
            FileNavigationBar(controller: controller),
            const Divider(height: 1),
          ],
          Expanded(
            child: _Body(
              controller: controller,
              onOpenFile: onOpenFile,
              onAction: onAction,
              rowWrapper: rowWrapper,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the context menu at the pointer and reports the choice.
Future<void> showFileContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<FileAction?> items,
  required List<AdbFileEntry> selection,
  required void Function(FileAction, List<AdbFileEntry>)? onAction,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final choice = await showMenu<FileAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    items: [
      for (final item in items)
        if (item == null)
          const PopupMenuDivider()
        else
          PopupMenuItem<FileAction>(
            value: item,
            // Disabled rather than hidden: a menu whose shape changes with
            // selection is harder to build muscle memory for.
            enabled: item.isEnabledFor(selection),
            child: Text(item.label),
          ),
    ],
  );

  if (choice != null) onAction?.call(choice, selection);
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    this.onOpenFile,
    this.onAction,
    this.rowWrapper,
  });

  final FileBrowserController controller;
  final void Function(AdbFileEntry)? onOpenFile;
  final void Function(FileAction, List<AdbFileEntry>)? onAction;
  final Widget Function(BuildContext, AdbFileEntry, Widget)? rowWrapper;

  @override
  Widget build(BuildContext context) {
    final listing = controller.listing;

    // Only the very first load shows a spinner. Later refreshes keep the
    // current listing on screen so the view does not flash empty.
    if (listing == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Each of these is a genuinely different situation and deserves its own
    // message. Collapsing them into "no files" is what hides a permission
    // problem behind an innocuous-looking empty folder.
    final message = switch (listing) {
      DirectoryDenied() => (
        Icons.lock_outline,
        'Permission denied',
        'The shell user cannot read this directory. Root access would be '
            'required.',
      ),
      DirectoryMissing() => (
        Icons.search_off,
        'Not found',
        'This path no longer exists.',
      ),
      DirectoryNotADirectory() => (
        Icons.insert_drive_file_outlined,
        'Not a directory',
        'This path points at a file.',
      ),
      DirectoryFailed(:final error) => (
        Icons.error_outline,
        'Could not read directory',
        '$error',
      ),
      DirectoryContents() => null,
    };

    if (message != null) {
      return _Placeholder(
        icon: message.$1,
        title: message.$2,
        detail: message.$3,
      );
    }

    final entries = controller.entries;
    if (entries.isEmpty) {
      final hiddenOnly = listing is DirectoryContents &&
          listing.entries.isNotEmpty &&
          !controller.showHidden;
      return _Placeholder(
        icon: Icons.folder_open,
        title: 'Empty folder',
        detail: hiddenOnly
            ? 'Only hidden items here. Enable "show hidden" to see them.'
            : null,
      );
    }

    return Column(
      children: [
        _SortHeader(controller: controller),
        const Divider(height: 1),
        Expanded(
          child: GestureDetector(
            // Right-click on empty space below the rows.
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) => showFileContextMenu(
              context: context,
              globalPosition: details.globalPosition,
              items: FileAction.backgroundMenu,
              selection: const [],
              onAction: onAction,
            ),
            onTap: controller.clearSelection,
            child: ListView.builder(
              itemCount: entries.length,
              itemExtent: 40,
              itemBuilder: (context, i) {
                final entry = entries[i];
                final row = _FileRow(
                  entry: entry,
                  selected: controller.selected.contains(entry.path),
                  onTap: () => _onTap(entry),
                  onDoubleTap: () => _onOpen(entry),
                  onSecondaryTapUp: (details) {
                    // Right-clicking outside the current selection replaces
                    // it, matching Finder; right-clicking inside keeps it so
                    // a multi-selection can be acted on.
                    if (!controller.selected.contains(entry.path)) {
                      controller.selectOnly(entry);
                    }
                    showFileContextMenu(
                      context: context,
                      globalPosition: details.globalPosition,
                      items: FileAction.rowMenu,
                      selection: controller.selectedEntries,
                      onAction: onAction,
                    );
                  },
                );
                return rowWrapper?.call(context, entry, row) ?? row;
              },
            ),
          ),
        ),
      ],
    );
  }

  void _onTap(AdbFileEntry entry) {
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) {
      controller.toggleSelection(entry);
    } else if (keys.isShiftPressed) {
      controller.selectRangeTo(entry);
    } else {
      controller.selectOnly(entry);
    }
  }

  void _onOpen(AdbFileEntry entry) {
    if (entry.isDirectory || entry.isSymlink) {
      controller.open(entry);
    } else {
      onOpenFile?.call(entry);
    }
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapUp,
  });

  final AdbFileEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(TapUpDetails) onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: onSecondaryTapUp,
      child: Container(
        color: selected ? theme.colorScheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(_iconFor(entry), size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // Hidden files are dimmed rather than hidden outright when
                  // the toggle is on, so they stay visually distinct.
                  color: entry.isHidden ? theme.disabledColor : null,
                  fontStyle: entry.isSymlink ? FontStyle.italic : null,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                // A directory's own inode size is meaningless to a user.
                entry.isDirectory ? '—' : formatBytes(entry.size),
                textAlign: TextAlign.right,
                style: muted,
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 130,
              child: Text(formatFileTime(entry.modified), style: muted),
            ),
            SizedBox(
              width: 96,
              child: Text(
                entry.permissionString,
                style: muted?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(AdbFileEntry entry) {
    if (entry.isDirectory) return Icons.folder;
    if (entry.isSymlink) return Icons.link;
    return switch (RemotePath.extension(entry.name)) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => Icons.image,
      'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' => Icons.movie,
      'mp3' || 'wav' || 'flac' || 'ogg' || 'm4a' => Icons.audiotrack,
      'zip' || 'gz' || 'tar' || 'xz' || '7z' || 'rar' => Icons.archive,
      'apk' => Icons.android,
      'pdf' => Icons.picture_as_pdf,
      'txt' || 'log' || 'json' || 'xml' || 'md' => Icons.description,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({required this.controller});

  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, FileSortField field, {double? width, int? flex}) {
      final active = controller.sort.field == field;
      final child = InkWell(
        onTap: () => controller.setSort(field),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: active ? FontWeight.bold : null,
              ),
            ),
            if (active)
              Icon(
                controller.sort.ascending
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
                size: 16,
              ),
          ],
        ),
      );
      return width != null
          ? SizedBox(width: width, child: child)
          : Expanded(flex: flex ?? 1, child: child);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 6, 12, 6),
      child: Row(
        children: [
          cell('Name', FileSortField.name, flex: 4),
          cell('Size', FileSortField.size, width: 90),
          const SizedBox(width: 16),
          cell('Modified', FileSortField.modified, width: 130),
          const SizedBox(width: 96),
        ],
      ),
    );
  }
}

/// Back / forward / up, refresh, and the hidden-files toggle.
class FileNavigationBar extends StatelessWidget {
  const FileNavigationBar({
    required this.controller,
    this.showBreadcrumbs = true,
    super.key,
  });

  final FileBrowserController controller;
  final bool showBreadcrumbs;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: controller.canGoBack ? controller.goBack : null,
            tooltip: 'Back',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: controller.canGoForward ? controller.goForward : null,
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: controller.canGoUp ? controller.goUp : null,
            tooltip: 'Up',
          ),
          if (showBreadcrumbs)
            Expanded(child: FileBreadcrumbs(controller: controller))
          else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.refresh,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(
              controller.showHidden ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () => controller.setShowHidden(!controller.showHidden),
            tooltip: 'Show hidden files',
          ),
        ],
      ),
    );
  }
}

/// Clickable path segments.
///
/// Separate from [FileNavigationBar] so it can live wherever the host app
/// wants — Finder puts its path bar along the bottom edge, not in the toolbar.
class FileBreadcrumbs extends StatelessWidget {
  const FileBreadcrumbs({
    required this.controller,
    this.compact = false,
    super.key,
  });

  final FileBrowserController controller;

  /// Tighter spacing and smaller text, for a status-bar-height strip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final crumbs = controller.breadcrumbs;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Anchored to the end so a deep path keeps the current folder
          // visible rather than scrolling it off the right edge.
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final crumb in crumbs) ...[
                _Crumb(
                  label: crumb == RemotePath.root
                      ? '/'
                      : RemotePath.basename(crumb),
                  // The last crumb is where you already are.
                  onTap: crumb == controller.path
                      ? null
                      : () => controller.navigateTo(crumb),
                  compact: compact,
                  current: crumb == controller.path,
                ),
                if (crumb != crumbs.last)
                  Icon(
                    Icons.chevron_right,
                    size: compact ? 12 : 14,
                    color: theme.disabledColor,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.onTap,
    required this.compact,
    required this.current,
  });

  final String label;
  final VoidCallback? onTap;
  final bool compact;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
        ?.copyWith(
          color: current ? theme.colorScheme.onSurface : theme.hintColor,
          fontWeight: current ? FontWeight.w600 : null,
        );

    if (!compact) {
      return TextButton(onPressed: onTap, child: Text(label, style: style));
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: style),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.title, this.detail});

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
