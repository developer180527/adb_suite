import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/material.dart';

/// The action bar above the file list.
///
/// Lives here rather than inside `browser_screen.dart` because the
/// disconnected skeleton shows the same bar in an inert state. Two copies drift
/// the moment a button is added to one of them; one widget with everything
/// optional cannot.
///
/// A null [browser] means "no device": every control disables itself, because
/// each `onPressed` is already derived from state that is absent. Nothing here
/// needs a separate `enabled` flag.
class BrowserToolbar extends StatelessWidget {
  const BrowserToolbar({
    this.browser,
    this.selected = const [],
    this.onDownload,
    this.onDelete,
    this.onRename,
    this.onNewFolder,
    this.onNewTab,
    this.onRevealDownloads,
    this.onDisconnect,
    super.key,
  });

  /// Null while no device is connected.
  final FileBrowserController? browser;
  final List<AdbFileEntry> selected;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onNewFolder;
  final VoidCallback? onNewTab;

  /// Null on platforms that cannot hand a folder to a file manager.
  final VoidCallback? onRevealDownloads;

  /// Null hides the button entirely — there is nothing to disconnect from.
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final browser = this.browser;
    final live = browser != null;
    final hasSelection = live && selected.isNotEmpty;
    final one = live && selected.length == 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: live && browser.canGoBack ? browser.goBack : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Forward',
            onPressed: live && browser.canGoForward ? browser.goForward : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Up  ⌘↑',
            onPressed: live && browser.canGoUp ? browser.goUp : null,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download…  ⌘D',
            onPressed: hasSelection ? onDownload : null,
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename',
            onPressed: one ? onRename : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Move to Trash  (hold Shift to delete permanently)',
            onPressed: hasSelection ? onDelete : null,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: live ? onNewFolder : null,
          ),
          IconButton(
            icon: const Icon(Icons.tab),
            tooltip: 'New tab  ⌘T',
            onPressed: live ? onNewTab : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh  ⌘R',
            onPressed: live ? browser.refresh : null,
          ),
          IconButton(
            icon: Icon(
              live && browser.showHidden
                  ? Icons.visibility
                  : Icons.visibility_off,
            ),
            tooltip: live && browser.showHidden
                ? 'Hide hidden files'
                : 'Show hidden files',
            onPressed:
                live ? () => browser.setShowHidden(!browser.showHidden) : null,
          ),
          const Spacer(),
          if (onRevealDownloads != null)
            TextButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Downloads'),
              onPressed: onRevealDownloads,
            ),
          if (onDisconnect != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Disconnect',
              onPressed: onDisconnect,
            ),
        ],
      ),
    );
  }
}
