import 'dart:async';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/foundation.dart';

/// One tab: either a directory listing or a file preview.
///
/// A preview tab keeps a [browser] too, pointed at the file's own folder, so
/// the sidebar, path bar, and navigation chrome all stay meaningful — and
/// closing the preview or navigating up lands somewhere sensible.
class BrowserTab {
  BrowserTab({required this.id, required this.browser, this.preview});

  final int id;
  final FileBrowserController browser;

  /// Non-null when this tab is showing a file rather than a directory.
  PreviewController? preview;

  bool get isPreview => preview != null;

  /// Keyboard cursor row. Per-tab so switching tabs restores where you were.
  int cursor = 0;

  String get title {
    final previewing = preview;
    if (previewing != null) return previewing.entry.name;

    final path = browser.path;
    if (path == RemotePath.root) return 'Device';
    final name = RemotePath.basename(path);
    // /sdcard is where everyone starts; its basename is not a useful label.
    return path == '/sdcard' ? 'Internal storage' : name;
  }
}

/// Owns the open tabs and which one is showing.
///
/// Each tab holds a full [FileBrowserController], so tabs are genuinely
/// independent — separate history, selection, sort, and scroll position —
/// rather than one browser whose path is swapped around.
class TabsController extends ChangeNotifier {
  TabsController({
    required FileService service,
    required AdbSession session,
    required RemoteFileServer server,
    required FileOpener opener,
    String initialPath = '/sdcard',
  }) : _service = service,
       _session = session,
       _server = server,
       _opener = opener {
    _open(initialPath);
  }

  final FileService _service;
  final AdbSession _session;
  final RemoteFileServer _server;
  final FileOpener _opener;
  final List<BrowserTab> _tabs = [];
  int _activeIndex = 0;
  int _nextId = 1;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  BrowserTab get active => _tabs[_activeIndex];
  FileBrowserController get browser => active.browser;
  bool get hasMultiple => _tabs.length > 1;

  BrowserTab _open(String path) {
    final tab = BrowserTab(
      id: _nextId++,
      browser: FileBrowserController(service: _service, initialPath: path),
    );
    // Retitle when the tab navigates.
    tab.browser.addListener(notifyListeners);
    _tabs.add(tab);
    return tab;
  }

  /// Opens a new tab and switches to it.
  ///
  /// Defaults to the current tab's directory, which is what Finder does and
  /// what you want when splitting off to compare two places.
  void newTab({String? path}) {
    final target = path ?? (_tabs.isEmpty ? '/sdcard' : browser.path);
    final tab = _open(target);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    tab.browser.load();
  }

  /// Opens [entry] as a preview in a new tab.
  ///
  /// Always a new tab rather than replacing the listing, so the folder you
  /// were browsing is still there when you are done looking.
  void openPreview(AdbFileEntry entry) {
    final tab = _open(RemotePath.parent(entry.path));
    tab.preview = PreviewController(
      session: _session,
      server: _server,
      entry: entry,
      opener: _opener,
    )..addListener(notifyListeners);

    _activeIndex = _tabs.length - 1;
    notifyListeners();
    // The containing directory is loaded too, so closing the preview or
    // navigating up shows the folder without another round trip.
    unawaited(tab.browser.load());
    unawaited(tab.preview!.load());
  }

  /// Turns a preview tab back into a directory listing.
  void closePreview(BrowserTab tab) {
    final preview = tab.preview;
    if (preview == null) return;
    tab.preview = null;
    preview
      ..removeListener(notifyListeners)
      ..dispose();
    notifyListeners();
    unawaited(tab.browser.load());
  }

  /// Closes a tab. Returns false when it was the last one, so the caller can
  /// decide whether to close the window instead.
  bool closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return true;
    if (_tabs.length == 1) return false;

    final tab = _tabs.removeAt(index);
    tab.preview
      ?..removeListener(notifyListeners)
      ..dispose();
    tab.browser
      ..removeListener(notifyListeners)
      ..dispose();

    // Keep the neighbour selected rather than jumping to the start.
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    if (index < _activeIndex) _activeIndex--;

    notifyListeners();
    return true;
  }

  bool closeActive() => closeTab(_activeIndex);

  void select(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Wraps around, matching every browser and Finder.
  void nextTab() => select((_activeIndex + 1) % _tabs.length);

  void previousTab() =>
      select((_activeIndex - 1 + _tabs.length) % _tabs.length);

  /// Cmd+1..8 select by position; Cmd+9 is always the last tab.
  void selectByNumber(int number) {
    if (number == 9) {
      select(_tabs.length - 1);
    } else if (number >= 1 && number <= _tabs.length) {
      select(number - 1);
    }
  }

  /// Loads the active tab if it has not fetched yet.
  void loadActive() => active.browser.load();

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.preview
        ?..removeListener(notifyListeners)
        ..dispose();
      tab.browser
        ..removeListener(notifyListeners)
        ..dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
