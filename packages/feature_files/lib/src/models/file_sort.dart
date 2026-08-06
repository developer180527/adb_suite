import 'package:adb_core/adb_core.dart';

import '../remote_path.dart';

enum FileSortField { name, size, modified, type }

class FileSort {
  const FileSort({
    this.field = FileSortField.name,
    this.ascending = true,
    this.directoriesFirst = true,
  });

  final FileSortField field;
  final bool ascending;

  /// Directories grouped above files regardless of the sort field, which is
  /// what every file manager does and what users expect.
  final bool directoriesFirst;

  FileSort toggled(FileSortField next) => field == next
      ? FileSort(
          field: field,
          ascending: !ascending,
          directoriesFirst: directoriesFirst,
        )
      : FileSort(field: next, directoriesFirst: directoriesFirst);

  List<AdbFileEntry> apply(List<AdbFileEntry> entries) {
    final sorted = [...entries]..sort(_compare);
    return sorted;
  }

  int _compare(AdbFileEntry a, AdbFileEntry b) {
    if (directoriesFirst && a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }

    final result = switch (field) {
      // Case-insensitive so "Zebra" does not sort above "apple", which is how
      // ASCII ordering would place it.
      FileSortField.name => _compareNames(a, b),
      FileSortField.size => a.size.compareTo(b.size),
      FileSortField.modified => _compareDates(a, b),
      FileSortField.type => RemotePath.extension(a.name)
          .compareTo(RemotePath.extension(b.name)),
    };

    // Ties fall back to name so ordering is stable and does not shuffle
    // between refreshes.
    final tiebreak = result != 0 ? result : _compareNames(a, b);
    return ascending ? tiebreak : -tiebreak;
  }

  static int _compareNames(AdbFileEntry a, AdbFileEntry b) {
    final result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return result != 0 ? result : a.name.compareTo(b.name);
  }

  /// Entries with no timestamp sort last rather than being treated as epoch.
  static int _compareDates(AdbFileEntry a, AdbFileEntry b) {
    final left = a.modified;
    final right = b.modified;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }
}
