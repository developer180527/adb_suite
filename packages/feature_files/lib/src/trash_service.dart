import 'dart:convert';

import 'package:adb_core/adb_core.dart';

import 'file_service.dart';
import 'models/directory_listing.dart';
import 'remote_path.dart';

/// Something moved to the trash, with enough recorded to put it back.
class TrashedItem {
  const TrashedItem({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.deletedAt,
    required this.isDirectory,
    required this.size,
  });

  /// Unique name inside the trash, so two files called `photo.jpg` deleted
  /// from different folders do not collide.
  final String id;

  final String name;
  final String originalPath;
  final DateTime deletedAt;
  final bool isDirectory;
  final int size;

  String get originalParent => RemotePath.parent(originalPath);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'originalPath': originalPath,
    'deletedAt': deletedAt.toIso8601String(),
    'isDirectory': isDirectory,
    'size': size,
  };

  static TrashedItem? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final originalPath = json['originalPath'];
    if (id is! String || name is! String || originalPath is! String) {
      return null;
    }
    return TrashedItem(
      id: id,
      name: name,
      originalPath: originalPath,
      deletedAt:
          DateTime.tryParse(json['deletedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isDirectory: json['isDirectory'] == true,
      size: json['size'] is int ? json['size']! as int : 0,
    );
  }
}

/// A recoverable delete.
///
/// Android gives the shell user no system trash, so this maintains its own,
/// laid out like the freedesktop.org spec: the item goes in `files/` and a
/// sibling record in `info/` remembers where it came from.
///
/// Deleting is a `mv` within the same filesystem, so it is instant and costs
/// no transfer regardless of size.
class TrashService {
  TrashService(this._service, {this.root = defaultRoot});

  final FileService _service;

  /// Lives on `/sdcard` because that is where the files being deleted almost
  /// always are, and `mv` is only instant within one filesystem.
  static const String defaultRoot = '/sdcard/.Trash-adb_files';

  final String root;

  String get _filesDir => '$root/files';
  String get _infoDir => '$root/info';

  Future<void> _ensure() async {
    await _service.createDirectory(_filesDir);
    await _service.createDirectory(_infoDir);
  }

  /// Moves [entry] to the trash and returns the record.
  Future<TrashedItem> moveToTrash(AdbFileEntry entry) async {
    if (RemotePath.isWithin(root, entry.path)) {
      throw ArgumentError('Already in the trash: ${entry.path}');
    }
    await _ensure();

    final id = _idFor(entry.name);
    final item = TrashedItem(
      id: id,
      name: entry.name,
      originalPath: entry.path,
      deletedAt: DateTime.now(),
      isDirectory: entry.isDirectory,
      size: entry.size,
    );

    // Write the record first. A stray record with no file is harmless and
    // gets pruned on list(); a file with no record is unrecoverable.
    await _writeInfo(item);
    try {
      await _service.move(entry.path, '$_filesDir/$id');
    } on Object {
      await _service.delete('$_infoDir/$id.json');
      rethrow;
    }

    return item;
  }

  Future<List<TrashedItem>> list() async {
    final listing = await _service.list(_infoDir);
    if (listing is! DirectoryContents) return const [];

    final items = <TrashedItem>[];
    for (final record in listing.entries) {
      if (!record.name.endsWith('.json')) continue;
      final item = await _readInfo(record.path);
      if (item == null) continue;
      // Drop records whose file is gone, so the trash never lists something
      // that cannot be restored.
      if (!await _service.exists('$_filesDir/${item.id}')) continue;
      items.add(item);
    }

    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  /// Puts an item back where it came from.
  ///
  /// If something now occupies the original name, restores alongside it under
  /// a deduplicated name rather than overwriting.
  Future<String> restore(TrashedItem item) async {
    final parent = item.originalParent;
    await _service.createDirectory(parent);

    var target = item.originalPath;
    if (await _service.exists(target)) {
      final siblings = await _service.list(parent);
      final taken = siblings is DirectoryContents
          ? siblings.entries.map((e) => e.name).toSet()
          : <String>{};
      target = RemotePath.join(parent, RemotePath.deduplicate(item.name, taken));
    }

    await _service.move('$_filesDir/${item.id}', target);
    await _service.delete('$_infoDir/${item.id}.json');
    return target;
  }

  Future<void> deletePermanently(TrashedItem item) async {
    await _service.delete('$_filesDir/${item.id}', recursive: item.isDirectory);
    await _service.delete('$_infoDir/${item.id}.json');
  }

  Future<void> empty() async {
    await _service.delete(root, recursive: true);
    await _ensure();
  }

  /// Total bytes held in the trash.
  Future<int> size() async => await _service.directorySize(_filesDir) ?? 0;

  Future<void> _writeInfo(TrashedItem item) async {
    // writeText base64-encodes, so the JSON's quotes and braces never reach
    // the shell as syntax. Avoids needing a local temp file just to trash.
    final json = jsonEncode(item.toJson());
    await _service.writeText('$_infoDir/${item.id}.json', json);
  }

  Future<TrashedItem?> _readInfo(String path) async {
    try {
      final text = await _service.readText(path);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return null;
      return TrashedItem.fromJson(decoded);
    } on Object {
      // A corrupt record must not break the whole listing.
      return null;
    }
  }

  /// Timestamp plus the original name keeps ids readable in a shell while
  /// staying unique to the millisecond.
  static String _idFor(String name) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safe = name.replaceAll(RegExp(r'[/\x00]'), '_');
    return '$stamp-$safe';
  }
}
