import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

AdbFileEntry _file(
  String name, {
  int size = 0,
  DateTime? modified,
  bool directory = false,
}) => AdbFileEntry(
  name: name,
  parentPath: '/sdcard',
  mode: directory ? 0x41ED : 0x81A4,
  size: size,
  modified: modified,
);

void main() {
  group('directoriesFirst', () {
    test('groups directories above files regardless of name', () {
      final sorted = const FileSort().apply([
        _file('apple.txt'),
        _file('Zebra', directory: true),
      ]);
      expect(sorted.map((e) => e.name), ['Zebra', 'apple.txt']);
    });

    test('still groups directories first when descending', () {
      final sorted = const FileSort(ascending: false).apply([
        _file('a.txt'),
        _file('b_dir', directory: true),
      ]);
      expect(sorted.first.name, 'b_dir');
    });

    test('can be turned off', () {
      final sorted = const FileSort(directoriesFirst: false).apply([
        _file('zebra', directory: true),
        _file('apple.txt'),
      ]);
      expect(sorted.map((e) => e.name), ['apple.txt', 'zebra']);
    });
  });

  group('name sorting', () {
    test('is case-insensitive', () {
      // Raw ASCII ordering would put every capital before every lowercase,
      // so "Zebra" would sort above "apple".
      final sorted = const FileSort().apply([
        _file('Zebra.txt'),
        _file('apple.txt'),
        _file('Mango.txt'),
      ]);
      expect(sorted.map((e) => e.name), [
        'apple.txt',
        'Mango.txt',
        'Zebra.txt',
      ]);
    });

    test('reverses when descending', () {
      final sorted = const FileSort(ascending: false).apply([
        _file('a.txt'),
        _file('b.txt'),
      ]);
      expect(sorted.map((e) => e.name), ['b.txt', 'a.txt']);
    });
  });

  group('size sorting', () {
    test('orders ascending by size', () {
      final sorted = const FileSort(field: FileSortField.size).apply([
        _file('big', size: 900),
        _file('small', size: 10),
      ]);
      expect(sorted.map((e) => e.name), ['small', 'big']);
    });

    test('equal sizes fall back to name for a stable order', () {
      final sorted = const FileSort(field: FileSortField.size).apply([
        _file('b', size: 5),
        _file('a', size: 5),
      ]);
      expect(sorted.map((e) => e.name), ['a', 'b']);
    });
  });

  group('date sorting', () {
    test('orders oldest first when ascending', () {
      final sorted = const FileSort(field: FileSortField.modified).apply([
        _file('new', modified: DateTime(2026, 8)),
        _file('old', modified: DateTime(2020, 1)),
      ]);
      expect(sorted.map((e) => e.name), ['old', 'new']);
    });

    test('entries with no timestamp sort last, not as the epoch', () {
      // Treating null as 1970 would jam every unknown-date file at the top.
      final sorted = const FileSort(field: FileSortField.modified).apply([
        _file('unknown'),
        _file('dated', modified: DateTime(2026, 8)),
      ]);
      expect(sorted.map((e) => e.name), ['dated', 'unknown']);
    });
  });

  group('toggled', () {
    test('flips direction when the same field is chosen again', () {
      const sort = FileSort();
      final next = sort.toggled(FileSortField.name);
      expect(next.field, FileSortField.name);
      expect(next.ascending, isFalse);
    });

    test('switches field and resets to ascending', () {
      const sort = FileSort(ascending: false);
      final next = sort.toggled(FileSortField.size);
      expect(next.field, FileSortField.size);
      expect(next.ascending, isTrue);
    });

    test('preserves the directoriesFirst preference', () {
      const sort = FileSort(directoriesFirst: false);
      expect(sort.toggled(FileSortField.size).directoriesFirst, isFalse);
    });
  });

  test('apply does not mutate the input list', () {
    final input = [_file('b'), _file('a')];
    const FileSort().apply(input);
    expect(input.map((e) => e.name), ['b', 'a']);
  });
}
