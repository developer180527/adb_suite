import 'package:adb_core/adb_core.dart';
import 'package:flutter/foundation.dart';

import 'file_service.dart';
import 'models/directory_listing.dart';
import 'models/file_sort.dart';
import 'remote_path.dart';

/// Navigation, sorting, and selection state for one browser pane.
class FileBrowserController extends ChangeNotifier {
  FileBrowserController({
    required FileService service,
    String initialPath = '/sdcard',
  }) : _service = service,
       _path = RemotePath.normalize(initialPath);

  final FileService _service;

  String _path;
  DirectoryListing? _listing;
  FileSort _sort = const FileSort();
  bool _loading = false;
  bool _showHidden = false;
  final Set<String> _selected = {};

  /// Back/forward history, holding paths only — re-reading a directory on
  /// navigation is cheap and avoids showing a stale listing.
  final List<String> _back = [];
  final List<String> _forward = [];

  /// Guards against an earlier, slower load overwriting a newer one when the
  /// user navigates faster than the device responds.
  int _loadToken = 0;

  String get path => _path;
  DirectoryListing? get listing => _listing;
  FileSort get sort => _sort;
  bool get isLoading => _loading;
  bool get showHidden => _showHidden;
  Set<String> get selected => Set.unmodifiable(_selected);
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  bool get canGoUp => _path != RemotePath.root;
  List<String> get breadcrumbs => RemotePath.ancestors(_path);

  /// Entries after hidden-file filtering and sorting. Empty for any listing
  /// that is not [DirectoryContents].
  List<AdbFileEntry> get entries {
    final current = _listing;
    if (current is! DirectoryContents) return const [];
    final visible = _showHidden
        ? current.entries
        : current.entries.where((e) => !e.isHidden).toList();
    return _sort.apply(visible);
  }

  Future<void> load() async {
    final token = ++_loadToken;
    _loading = true;
    notifyListeners();

    final result = await _service.list(_path);

    // A newer navigation started while this was in flight; discard.
    if (token != _loadToken) return;

    _listing = result;
    _loading = false;
    _selected.clear();
    notifyListeners();
  }

  Future<void> refresh() => load();

  Future<void> navigateTo(String target) async {
    final normalized = RemotePath.normalize(target);
    if (normalized == _path) return;
    _back.add(_path);
    _forward.clear();
    _path = normalized;
    await load();
  }

  Future<void> open(AdbFileEntry entry) async {
    // Symlinks to directories are common on Android (/sdcard itself is one).
    // Trying to enter and falling back is more reliable than guessing from
    // the mode bits, which describe the link and not its target.
    if (entry.isDirectory || entry.isSymlink) {
      await navigateTo(entry.path);
    }
  }

  Future<void> goUp() async {
    if (!canGoUp) return;
    await navigateTo(RemotePath.parent(_path));
  }

  Future<void> goBack() async {
    if (_back.isEmpty) return;
    _forward.add(_path);
    _path = _back.removeLast();
    await load();
  }

  Future<void> goForward() async {
    if (_forward.isEmpty) return;
    _back.add(_path);
    _path = _forward.removeLast();
    await load();
  }

  void setSort(FileSortField field) {
    _sort = _sort.toggled(field);
    notifyListeners();
  }

  void setShowHidden(bool value) {
    if (_showHidden == value) return;
    _showHidden = value;
    _selected.clear();
    notifyListeners();
  }

  /// Anchor for shift-click range selection.
  String? _anchor;

  void toggleSelection(AdbFileEntry entry) {
    _selected.contains(entry.path)
        ? _selected.remove(entry.path)
        : _selected.add(entry.path);
    _anchor = entry.path;
    notifyListeners();
  }

  /// Replaces the selection with just [entry] — a plain click.
  void selectOnly(AdbFileEntry entry) {
    _selected
      ..clear()
      ..add(entry.path);
    _anchor = entry.path;
    notifyListeners();
  }

  /// Extends the selection from the anchor to [entry] — a shift-click.
  ///
  /// Ranges run over the *displayed* order, so what gets selected matches what
  /// the user sees rather than the underlying listing order.
  void selectRangeTo(AdbFileEntry entry) {
    final visible = entries;
    final anchorPath = _anchor;
    final end = visible.indexWhere((e) => e.path == entry.path);
    if (end < 0) return;

    final start = anchorPath == null
        ? end
        : visible.indexWhere((e) => e.path == anchorPath);
    if (start < 0) {
      selectOnly(entry);
      return;
    }

    final from = start <= end ? start : end;
    final to = start <= end ? end : start;
    _selected
      ..clear()
      ..addAll(visible.sublist(from, to + 1).map((e) => e.path));
    notifyListeners();
  }

  /// Entries currently selected, in displayed order.
  List<AdbFileEntry> get selectedEntries =>
      entries.where((e) => _selected.contains(e.path)).toList();

  void selectAll() {
    _selected
      ..clear()
      ..addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Names already present, so a new file or folder can avoid colliding.
  Set<String> get existingNames {
    final current = _listing;
    if (current is! DirectoryContents) return const {};
    return current.entries.map((e) => e.name).toSet();
  }

  Future<void> createDirectory(String name) async {
    await _service.createDirectory(RemotePath.join(_path, name));
    await refresh();
  }

  Future<void> deleteSelected() async {
    // Directories need -r; ask per entry rather than forcing recursive on
    // everything, so a stray selection cannot wipe a tree unexpectedly.
    final current = _listing;
    final byPath = current is DirectoryContents
        ? {for (final e in current.entries) e.path: e}
        : <String, AdbFileEntry>{};

    for (final path in _selected.toList()) {
      await _service.delete(
        path,
        recursive: byPath[path]?.isDirectory ?? false,
      );
    }
    await refresh();
  }

  Future<void> rename(AdbFileEntry entry, String newName) async {
    await _service.rename(entry.path, newName);
    await refresh();
  }

  @override
  void dispose() {
    // Invalidate any in-flight load so its notifyListeners never fires.
    _loadToken++;
    super.dispose();
  }
}
