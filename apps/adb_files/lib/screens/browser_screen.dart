import 'dart:async';
import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:adb_ui/adb_ui.dart';
import 'package:feature_files/feature_files.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_options.dart';
import '../state/app_settings.dart';
import '../state/connection_controller.dart';
import '../state/tabs_controller.dart';
import '../widgets/browser_toolbar.dart';
import '../widgets/document_viewer.dart';
import '../widgets/drag_drop.dart';
import '../widgets/media_viewer.dart';
import '../widgets/native_menu.dart';
import 'settings_view.dart';
import '../widgets/sidebar.dart';
import '../widgets/tab_bar.dart';
import '../widgets/transfer_panel.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    required this.connection,
    required this.settings,
    this.initialPath,
    super.key,
  });

  final ConnectionController connection;
  final AppSettings settings;

  /// Where the first tab opens. Set when this window was torn off a tab.
  final String? initialPath;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final TabsController _tabs;
  late final FileService _files;
  late final TransferManager _transfers;
  late final FileOpener _opener;
  late final TrashService _trash;
  late final RemoteFileServer _server;

  final _focusNode = FocusNode();
  ({int available, int total})? _freeSpace;
  bool _transfersExpanded = true;

  /// Remote paths currently being fetched for an "open", so a second
  /// double-click does not start a duplicate download.
  final Set<String> _opening = {};

  /// Bytes currently held in the preview cache, shown in Settings.
  int? _cacheSize;

  /// Non-null while a recursive tree is being enumerated. Walking a big folder
  /// takes a noticeable moment before any transfer starts, and silence there
  /// reads as a hang.
  String? _scanning;

  /// Shorthand for the active tab's browser.
  FileBrowserController get _browser => _tabs.browser;

  @override
  void initState() {
    super.initState();
    _files = widget.connection.fileService!;
    _transfers = widget.connection.transfers!;
    // Cache under the OS cache directory so it can be reclaimed under disk
    // pressure and does not clutter Documents.
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    _opener = FileOpener(
      _files,
      cacheDirectory: Directory('$home/Library/Caches/com.adbsuite.adbFiles'),
    );
    _trash = TrashService(_files);
    _server = RemoteFileServer(widget.connection.session!);
    _tabs = TabsController(
      service: _files,
      session: widget.connection.session!,
      server: _server,
      opener: _opener,
      initialPath: widget.initialPath ?? '/sdcard',
    )..addListener(_onTabsChanged);
    _tabs.loadActive();
    _refreshFreeSpace();
    unawaited(_refreshCacheSize());
  }

  Future<void> _refreshCacheSize() async {
    final size = await _opener.cacheSize();
    if (mounted) setState(() => _cacheSize = size);
  }

  Future<void> _clearCache() async {
    await _opener.clearCache();
    await _refreshCacheSize();
    if (mounted) _toast('Preview cache cleared');
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabsChanged)
      ..dispose();
    unawaited(_server.stop());
    _focusNode.dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    // Keep the cursor inside the list when the directory changes under it.
    final tab = _tabs.active;
    final count = tab.browser.entries.length;
    if (tab.cursor >= count) tab.cursor = count == 0 ? 0 : count - 1;
    if (mounted) setState(() {});
  }

  Future<void> _refreshFreeSpace() async {
    final space = await _files.freeSpace('/sdcard');
    if (mounted) setState(() => _freeSpace = space);
  }

  // --- tabs and windows ---

  void _newTab() {
    _tabs.newTab();
    _focusNode.requestFocus();
  }

  void _closeTab() {
    if (_tabs.closeActive()) return;
    // The last tab. On desktop that means closing the window; on iOS there is
    // no window to close and calling exit() is both wrong and grounds for App
    // Store rejection, so leave the tab open.
    if (_isDesktop) _closeWindow();
  }

  /// True where the app manages its own windows and can talk to other apps.
  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  void _closeWindow() {
    // No Flutter API for closing a desktop window; exiting is equivalent for
    // a single-window instance, and each Cmd+N spawns its own process.
    exit(0);
  }

  /// Opens a genuinely separate window.
  ///
  /// Flutter has no stable multi-window support, so rather than fight it with
  /// a plugin, this launches another instance of the app bundle. `open -n`
  /// forces a new process, and each instance gets its own adb session — the
  /// adb server handles concurrent clients fine.
  Future<void> _newWindow({List<String> args = const []}) async {
    if (!Platform.isMacOS) {
      _toast('New windows are only supported on macOS for now.');
      return;
    }
    // .../adb_files.app/Contents/MacOS/adb_files -> .../adb_files.app
    final executable = File(Platform.resolvedExecutable);
    final bundle = executable.parent.parent.parent;
    if (!bundle.path.endsWith('.app')) {
      _toast('Cannot locate the app bundle to open a new window.');
      return;
    }
    // `-a` is required: `open -n <path> --args ...` silently discards the
    // arguments, which is how a detached window ends up at the default path
    // and size instead of the ones it was given.
    await Process.run('open', [
      '-n',
      '-a',
      bundle.path,
      if (args.isNotEmpty) ...['--args', ...args],
    ]);
  }

  /// Tears a tab out into its own window, Chrome-style.
  ///
  /// The new window is a new process, so the tab's directory and this
  /// window's size travel in argv. Size is read natively before the engine
  /// starts, so the detached window never appears at the wrong size and then
  /// resizes.
  Future<void> _detachTab(int index) async {
    // The window *is* the last tab; there is nothing to detach it from.
    if (!_tabs.hasMultiple) return;
    final tab = _tabs.tabs[index];
    final path = tab.browser.path;

    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;

    await _newWindow(
      args: AppOptions.buildArgs(
        path: path,
        width: size.width,
        height: size.height,
        // Skip adb discovery and device tracking in the child; this window
        // already knows both answers.
        adbPath: widget.connection.transport?.binaryPath,
        serial: widget.connection.device?.serial,
      ),
    );

    // Only drop the tab once the new window has been asked for, so a failed
    // spawn does not lose it.
    _tabs.closeTab(index);
  }

  // --- actions ---

  String get _downloadsDir {
    final home = Platform.environment['HOME'];
    if (home == null) return Directory.systemTemp.path;
    // On iOS, HOME is the app container. ~/Downloads there would be invisible
    // to the user; Documents is surfaced by UIFileSharingEnabled and shows up
    // in the Files app.
    return _isDesktop ? '$home/Downloads' : '$home/Documents';
  }

  /// Asks where to save, then queues the transfers.
  ///
  /// A single file gets a save panel with an editable name; anything else gets
  /// a folder chooser, because there is no sensible single filename for a
  /// multi-item or recursive download.
  Future<void> _download(List<AdbFileEntry> entries) async {
    if (entries.isEmpty) return;

    final singleFile = entries.length == 1 && !entries.single.isDirectory;

    String destinationDir;
    String? exactName;

    if (singleFile) {
      final location = await getSaveLocation(
        suggestedName: entries.single.name,
        initialDirectory: _downloadsDir,
      );
      if (location == null) return; // cancelled
      final file = File(location.path);
      destinationDir = file.parent.path;
      exactName = file.uri.pathSegments.last;
    } else {
      final directory = await getDirectoryPath(
        initialDirectory: _downloadsDir,
        confirmButtonText: 'Download Here',
      );
      if (directory == null) return; // cancelled
      destinationDir = directory;
    }

    await _downloadTo(entries, destinationDir, exactName: exactName);
  }

  /// Queues [entries] into [destinationDir] without prompting.
  Future<void> _downloadTo(
    List<AdbFileEntry> entries,
    String destinationDir, {
    String? exactName,
  }) async {
    final directory = Directory(destinationDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);

    final taken = directory
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toSet();

    var queuedFiles = 0;
    final problems = <String>[];

    for (final entry in entries) {
      if (entry.isDirectory) {
        setState(() => _scanning = entry.name);
        try {
          final walk = await _transfers.enqueueDirectoryPull(
            entry.path,
            directory.path,
            onScanProgress: (files, bytes) {
              if (mounted) {
                setState(() => _scanning = '${entry.name}: $files files');
              }
            },
          );
          queuedFiles += walk.fileCount;

          // A partial copy must never look complete.
          if (walk.skipped.isNotEmpty) {
            problems.add(
              '${walk.skipped.length} unreadable folder(s) in ${entry.name}',
            );
          }
          if (walk.truncated) {
            problems.add('${entry.name} was too large to copy entirely');
          }
          if (walk.unsupported.isNotEmpty) {
            problems.add(
              '${walk.unsupported.length} item(s) in ${entry.name} could not '
              'be copied (links or special files)',
            );
          }
        } on Object catch (e) {
          problems.add('Could not scan ${entry.name}: $e');
        } finally {
          if (mounted) setState(() => _scanning = null);
        }
      } else {
        // The save panel already confirmed an overwrite, so an exact name is
        // used verbatim; otherwise avoid clobbering.
        final name = exactName ?? RemotePath.deduplicate(entry.name, taken);
        taken.add(name);
        _transfers.enqueuePull(entry.path, '${directory.path}/$name');
        queuedFiles++;
      }
    }

    if (!mounted) return;
    if (queuedFiles > 0) setState(() => _transfersExpanded = true);
    if (problems.isNotEmpty) _toast(problems.join(' · '));
  }

  Future<void> _revealDownloads() async {
    if (!FileOpener.canOpenExternally) return;
    await Process.run('open', [_downloadsDir]);
  }

  /// Downloads a file into the cache and hands it to the desktop's default
  /// application. This is what "opening" a device file means — the OS can only
  /// open something that exists locally.
  Future<void> _open(AdbFileEntry entry, {bool revealOnly = false}) async {
    if (entry.isDirectory) {
      await _browser.open(entry);
      return;
    }
    // Previewing in a tab streams rather than downloading, so it is the
    // default; "Open in default app" stays available for a real local copy.
    if (!revealOnly) {
      _tabs.openPreview(entry);
      return;
    }
    if (_opening.contains(entry.path)) return;

    final cached = _opener.isFresh(entry);
    setState(() => _opening.add(entry.path));
    if (!cached) _toast('Downloading ${entry.name}…');

    try {
      final file = await _opener.ensureLocal(entry);
      if (revealOnly) {
        await FileOpener.revealLocal(file.path);
      } else {
        await FileOpener.openLocal(file.path);
      }
    } on Object catch (e) {
      _toast('Could not open ${entry.name}: $e');
    } finally {
      if (mounted) setState(() => _opening.remove(entry.path));
    }
  }

  /// Downloads to the cache and hands the file to the desktop.
  ///
  /// Distinct from preview: this is for when the user genuinely wants the
  /// file in another application, which needs a real path on disk.
  Future<void> _openExternally(AdbFileEntry entry) async {
    if (entry.isDirectory) return;
    if (!FileOpener.canOpenExternally) {
      _toast('Opening in another app is not supported on this platform.');
      return;
    }
    if (_opening.contains(entry.path)) return;

    final cached = _opener.isFresh(entry);
    setState(() => _opening.add(entry.path));
    if (!cached) _toast('Downloading ${entry.name}…');
    try {
      final file = await _opener.ensureLocal(entry);
      await FileOpener.openLocal(file.path);
    } on Object catch (e) {
      _toast('Could not open ${entry.name}: $e');
    } finally {
      if (mounted) setState(() => _opening.remove(entry.path));
    }
  }

  /// Handles files and folders dropped in from Finder.
  Future<void> _uploadDropped(List<String> localPaths) async {
    final taken = {..._browser.existingNames};
    var queued = 0;

    for (final path in localPaths) {
      if (isLocalDirectory(path)) {
        final name = path.split(Platform.pathSeparator).last;
        setState(() => _scanning = name);
        try {
          queued += await _transfers.enqueueDirectoryPush(
            path,
            _browser.path,
            onScanProgress: (files) {
              if (mounted) setState(() => _scanning = '$name: $files files');
            },
          );
        } on Object catch (e) {
          _toast('Could not upload $name: $e');
        } finally {
          if (mounted) setState(() => _scanning = null);
        }
      } else {
        final base = path.split(Platform.pathSeparator).last;
        final name = RemotePath.deduplicate(base, taken);
        taken.add(name);
        _transfers.enqueuePush(path, RemotePath.join(_browser.path, name));
        queued++;
      }
    }

    if (!mounted) return;
    if (queued > 0) {
      setState(() => _transfersExpanded = true);
      unawaited(_refreshAfterTransfers());
    } else {
      _toast('Nothing to upload.');
    }
  }

  /// Refreshes once the queue drains, so uploaded files appear.
  Future<void> _refreshAfterTransfers() async {
    while (_transfers.isBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;
    await _browser.refresh();
    unawaited(_refreshFreeSpace());
  }

  /// Moves to the trash by default; holding Shift deletes outright.
  ///
  /// Trashing is a rename within the same filesystem, so it is instant even
  /// for a folder of videos, and it is recoverable — which matters more here
  /// than in a normal file manager, because there is no system-level undo for
  /// anything done over ADB.
  Future<void> _delete(List<AdbFileEntry> entries) async {
    if (entries.isEmpty) return;
    final permanent = HardwareKeyboard.instance.isShiftPressed;

    if (permanent) {
      final confirmed = await _confirmPermanent(entries);
      if (confirmed != true) return;
    }

    try {
      final trashed = <TrashedItem>[];
      for (final entry in entries) {
        if (permanent) {
          await _files.delete(entry.path, recursive: entry.isDirectory);
        } else {
          trashed.add(await _trash.moveToTrash(entry));
        }
      }
      await _browser.refresh();
      unawaited(_refreshFreeSpace());

      if (!mounted) return;
      if (permanent) {
        _toast('Deleted ${entries.length} item(s) permanently');
      } else {
        _showUndo(trashed);
      }
    } on Object catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<bool?> _confirmPermanent(List<AdbFileEntry> entries) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        entries.length == 1
            ? 'Permanently delete "${entries.single.name}"?'
            : 'Permanently delete ${entries.length} items?',
      ),
      content: Text(
        entries.any((e) => e.isDirectory)
            ? 'Folders and everything inside them will be removed from the '
                  'device. This bypasses the Trash and cannot be undone.'
            : 'This bypasses the Trash and cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Permanently'),
        ),
      ],
    ),
  );

  /// A snackbar with a working Undo, so trashing needs no confirmation at all.
  void _showUndo(List<TrashedItem> trashed) {
    if (trashed.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            trashed.length == 1
                ? 'Moved "${trashed.single.name}" to Trash'
                : 'Moved ${trashed.length} items to Trash',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                for (final item in trashed) {
                  await _trash.restore(item);
                }
                await _browser.refresh();
              } on Object catch (e) {
                _toast('Could not restore: $e');
              }
            },
          ),
        ),
      );
  }

  Future<void> _emptyTrash() async {
    final items = await _trash.list();
    if (items.isEmpty) {
      _toast('Trash is empty');
      return;
    }
    if (!mounted) return;

    final size = await _trash.size();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Empty Trash (${items.length} items)?'),
        content: Text(
          '${formatBytes(size)} will be permanently removed from the device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _trash.empty();
    await _browser.refresh();
    unawaited(_refreshFreeSpace());
    if (mounted) _toast('Trash emptied');
  }

  Future<void> _rename(AdbFileEntry entry) async {
    final name = await _prompt(
      title: 'Rename',
      initial: entry.name,
      label: 'Name',
    );
    if (name == null || name.isEmpty || name == entry.name) return;
    try {
      await _browser.rename(entry, name);
    } on Object catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _newFolder() async {
    final name = await _prompt(title: 'New folder', label: 'Folder name');
    if (name == null || name.isEmpty) return;
    try {
      await _browser.createDirectory(name);
    } on Object catch (e) {
      _toast('Could not create folder: $e');
    }
  }

  Future<void> _duplicate(AdbFileEntry entry) async {
    final name = RemotePath.deduplicate(entry.name, _browser.existingNames);
    try {
      await _files.copy(
        entry.path,
        RemotePath.join(_browser.path, name),
        recursive: entry.isDirectory,
      );
      await _browser.refresh();
    } on Object catch (e) {
      _toast('Duplicate failed: $e');
    }
  }

  Future<void> _copyPath(List<AdbFileEntry> entries) async {
    await Clipboard.setData(
      ClipboardData(text: entries.map((e) => e.path).join('\n')),
    );
    _toast(entries.length == 1 ? 'Path copied' : '${entries.length} paths copied');
  }

  Future<void> _showProperties(AdbFileEntry entry) async {
    // Directory sizes need `du`, which is a round trip, so only fetch it when
    // the user actually asks for info.
    int? size = entry.isDirectory ? null : entry.size;
    if (entry.isDirectory) size = await _files.directorySize(entry.path);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('Path', entry.path),
            _InfoRow('Kind', entry.type.name),
            _InfoRow('Size', size == null ? 'unknown' : formatBytes(size)),
            _InfoRow('Modified', formatFileTime(entry.modified)),
            _InfoRow('Permissions', entry.permissionString),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<String?> _prompt({
    required String title,
    required String label,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Single dispatch point for the toolbar, keyboard, menu bar, and context
  /// menu, so none of them can drift apart.
  Future<void> _runAction(FileAction action, List<AdbFileEntry> selection) async {
    switch (action) {
      case FileAction.open:
        if (selection.length == 1) await _open(selection.single);
      case FileAction.openWith:
        if (selection.length == 1) await _openExternally(selection.single);
      case FileAction.download:
        await _download(selection);
      case FileAction.rename:
        if (selection.length == 1) await _rename(selection.single);
      case FileAction.duplicate:
        if (selection.length == 1) await _duplicate(selection.single);
      case FileAction.delete:
        await _delete(selection);
      case FileAction.newFolder:
        await _newFolder();
      case FileAction.copyPath:
        await _copyPath(selection);
      case FileAction.refresh:
        await _browser.refresh();
      case FileAction.properties:
        if (selection.length == 1) await _showProperties(selection.single);
    }
  }

  /// Viewers that need heavy native libraries live here rather than in
  /// feature_files, so the package stays usable without libmpv or PDFium.
  Map<PreviewKind, PreviewViewerBuilder> get _previewBuilders => {
    PreviewKind.video: (context, preview) => MediaViewer(
      key: ValueKey('video-${preview.entry.path}'),
      url: preview.url!,
      isAudio: false,
      title: preview.entry.name,
    ),
    PreviewKind.audio: (context, preview) => MediaViewer(
      key: ValueKey('audio-${preview.entry.path}'),
      url: preview.url!,
      isAudio: true,
      title: preview.entry.name,
    ),
    PreviewKind.pdf: (context, preview) {
      final file = preview.localFile;
      if (file == null) return null;
      return DevicePdfViewer(
        key: ValueKey('pdf-${preview.entry.path}'),
        file: file,
      );
    },
    PreviewKind.document: (context, preview) {
      final file = preview.localFile;
      if (file == null || !QuickLookViewer.isSupported) return null;
      return QuickLookViewer(
        key: ValueKey('doc-${preview.entry.path}'),
        file: file,
        name: preview.entry.name,
        onOpenExternally: () => unawaited(_openExternally(preview.entry)),
      );
    },
  };

  // --- keyboard ---

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final entries = _browser.entries;
    final tab = _tabs.active;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Tab management first: these must win over navigation.
    if (meta) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyT:
          _newTab();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyW:
          _closeTab();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyN:
          unawaited(_newWindow());
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketRight:
          _tabs.nextTab();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketLeft:
          _tabs.previousTab();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.tab:
          shift ? _tabs.previousTab() : _tabs.nextTab();
          return KeyEventResult.handled;
      }

      // Cmd+1..9 jump to a tab by position.
      final digit = _digitFor(event.logicalKey);
      if (digit != null) {
        _tabs.selectByNumber(digit);
        return KeyEventResult.handled;
      }
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when !meta:
        if (entries.isEmpty) return KeyEventResult.handled;
        setState(() => tab.cursor = (tab.cursor + 1).clamp(0, entries.length - 1));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp when !meta:
        if (entries.isEmpty) return KeyEventResult.handled;
        setState(() => tab.cursor = (tab.cursor - 1).clamp(0, entries.length - 1));
        return KeyEventResult.handled;

      // Finder conventions: Cmd+Down opens, Cmd+Up goes to the parent.
      case LogicalKeyboardKey.arrowRight when !meta:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.arrowDown when meta:
        if (tab.cursor < entries.length) unawaited(_open(entries[tab.cursor]));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft when !meta:
      case LogicalKeyboardKey.arrowUp when meta:
      case LogicalKeyboardKey.backspace when !meta:
        unawaited(_browser.goUp());
        return KeyEventResult.handled;

      case LogicalKeyboardKey.space:
        if (tab.cursor < entries.length) {
          _browser.toggleSelection(entries[tab.cursor]);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyA when meta:
        _browser.selectAll();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyR when meta:
        unawaited(_browser.refresh());
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyD when meta:
        unawaited(_download(_selectedOrCursor()));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyC when meta:
        unawaited(_copyPath(_selectedOrCursor()));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyI when meta:
        final one = _selectedOrCursor();
        if (one.length == 1) unawaited(_showProperties(one.single));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.escape:
        if (_tabs.active.isPreview) {
          _tabs.closePreview(_tabs.active);
        } else {
          _browser.clearSelection();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace when meta:
        unawaited(_delete(_selectedOrCursor()));
        return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  static int? _digitFor(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final index = digits.indexOf(key);
    return index < 0 ? null : index + 1;
  }

  List<AdbFileEntry> _selectedOrCursor() {
    final entries = _browser.entries;
    if (_browser.selected.isNotEmpty) return _browser.selectedEntries;
    final cursor = _tabs.active.cursor;
    if (cursor < entries.length) return [entries[cursor]];
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selectedOrCursor();

    return PlatformMenuBar(
      // A real Mac app puts its shortcuts in the menu bar, so they are
      // discoverable rather than folklore.
      menus: [
        // On macOS the FIRST menu becomes the application menu, whatever it is
        // called. Without this placeholder, "File" gets absorbed and never
        // appears in the menu bar.
        PlatformMenu(
          label: 'Files',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hide,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Tab',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
              onSelected: _newTab,
            ),
            PlatformMenuItem(
              label: 'New Window',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
              onSelected: () => unawaited(_newWindow()),
            ),
            PlatformMenuItem(
              label: 'Close Tab',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
              onSelected: _closeTab,
            ),
            PlatformMenuItem(
              label: 'New Folder',
              onSelected: () => unawaited(_newFolder()),
            ),
            PlatformMenuItem(
              label: 'Download…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyD, meta: true),
              onSelected: selection.isEmpty
                  ? null
                  : () => unawaited(_download(selection)),
            ),
            PlatformMenuItem(
              label: 'Empty Trash…',
              onSelected: () => unawaited(_emptyTrash()),
            ),
            PlatformMenuItem(
              label: 'Get Info',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
              onSelected: selection.length == 1
                  ? () => unawaited(_showProperties(selection.single))
                  : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Go',
          menus: [
            PlatformMenuItem(
              label: 'Back',
              onSelected: _browser.canGoBack
                  ? () => unawaited(_browser.goBack())
                  : null,
            ),
            PlatformMenuItem(
              label: 'Forward',
              onSelected: _browser.canGoForward
                  ? () => unawaited(_browser.goForward())
                  : null,
            ),
            PlatformMenuItem(
              label: 'Enclosing Folder',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.arrowUp,
                meta: true,
              ),
              onSelected:
                  _browser.canGoUp ? () => unawaited(_browser.goUp()) : null,
            ),
            PlatformMenuItem(
              label: 'Refresh',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
              onSelected: () => unawaited(_browser.refresh()),
            ),
          ],
        ),
      ],
      child: Scaffold(
        body: Row(
          children: [
            Sidebar(
              controller: _browser,
              deviceName: widget.connection.device?.displayName ?? 'Device',
              freeSpace: _freeSpace,
              onOpenSettings: _tabs.openSettings,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  BrowserToolbar(
                    browser: _browser,
                    selected: selection,
                    onDownload: () => unawaited(_download(selection)),
                    onDelete: () => unawaited(_delete(selection)),
                    onRename: () {
                      if (selection.length == 1) unawaited(_rename(selection.single));
                    },
                    onNewFolder: () => unawaited(_newFolder()),
                    onNewTab: _newTab,
                    onRevealDownloads: FileOpener.canOpenExternally
                        ? () => unawaited(_revealDownloads())
                        : null,
                    onDisconnect: widget.connection.disconnect,
                  ),
                  const Divider(height: 1),
                  BrowserTabBar(
                    controller: _tabs,
                    onNewTab: _newTab,
                    onDetach: (i) => unawaited(_detachTab(i)),
                  ),
                  Expanded(
                    child: _tabs.active.isSettings
                        ? SettingsView(
                            settings: widget.settings,
                            cacheSize: _cacheSize,
                            onClearCache: _clearCache,
                          )
                        : _tabs.active.isPreview
                        ? PreviewView(
                            key: ValueKey('preview-${_tabs.active.id}'),
                            controller: _tabs.active.preview!,
                            builders: _previewBuilders,
                            onOpenExternally: () => unawaited(
                              _openExternally(_tabs.active.preview!.entry),
                            ),
                          )
                        : Focus(
                      focusNode: _focusNode,
                      autofocus: true,
                      onKeyEvent: _onKey,
                      child: GestureDetector(
                        onTap: _focusNode.requestFocus,
                        child: UploadDropTarget(
                          destinationLabel: RemotePath.basename(_browser.path),
                          onFilesDropped: (paths) =>
                              unawaited(_uploadDropped(paths)),
                          child: FileBrowser(
                            // Rebuild the list when the tab changes so state
                            // does not leak between tabs.
                            key: ValueKey(_tabs.active.id),
                            controller: _browser,
                            // Navigation lives in the toolbar and the path in
                            // the status bar, Finder-style.
                            showNavigationBar: false,
                            onOpenFile: (entry) => unawaited(_open(entry)),
                            onAction: (action, entries) =>
                                unawaited(_runAction(action, entries)),
                            // A real NSMenu on macOS; Material elsewhere.
                            menuPresenter: NativeContextMenu.show,
                            rowWrapper: (context, entry, child) =>
                                DraggableFileRow(
                                  entry: entry,
                                  opener: _opener,
                                  onFetchStart: (e) =>
                                      _toast('Fetching ${e.name} to drag…'),
                                  onFetchEnd: (e, error) {
                                    if (error != null) {
                                      _toast('Could not fetch ${e.name}: $error');
                                    }
                                  },
                                  child: child,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _StatusBar(browser: _browser, scanning: _scanning),
                  TransferPanel(
                    manager: _transfers,
                    expanded: _transfersExpanded,
                    onToggle: () => setState(
                      () => _transfersExpanded = !_transfersExpanded,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Finder-style bottom bar: the clickable path on the left, counts on the
/// right. Putting the path here rather than in the toolbar keeps the top of
/// the window for actions and gives long paths the full window width.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.browser, this.scanning});

  final FileBrowserController browser;
  final String? scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = browser.entries;
    final selected = browser.selected.length;
    final bytes = entries
        .where((e) => !e.isDirectory)
        .fold<int>(0, (sum, e) => sum + e.size);

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.only(left: 6, right: 12),
      child: Row(
        children: [
          Flexible(child: FileBreadcrumbs(controller: browser, compact: true)),
          const Spacer(),
          if (scanning != null) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('Scanning $scanning…', style: theme.textTheme.bodySmall),
            const SizedBox(width: 12),
          ] else if (browser.isLoading) ...[
            const SizedBox(
              width: 60,
              child: LinearProgressIndicator(minHeight: 2),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            selected > 0
                ? '$selected of ${entries.length} selected'
                : '${entries.length} items · ${formatBytes(bytes)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
