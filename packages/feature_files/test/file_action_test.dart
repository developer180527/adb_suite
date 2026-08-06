import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

AdbFileEntry _entry(String name, {bool directory = false}) => AdbFileEntry(
  name: name,
  parentPath: '/sdcard',
  mode: directory ? 0x41ED : 0x81A4,
  size: 100,
  modified: DateTime(2026, 8, 6),
);

void main() {
  final file = _entry('a.txt');
  final other = _entry('b.txt');
  final folder = _entry('Docs', directory: true);

  group('single-selection actions', () {
    test('open applies to exactly one file', () {
      expect(FileAction.open.isEnabledFor([file]), isTrue);
      expect(FileAction.open.isEnabledFor([file, other]), isFalse);
      expect(FileAction.open.isEnabledFor([]), isFalse);
    });

    test('open does not apply to a directory', () {
      // Opening a folder means navigating, which the row tap already does.
      expect(FileAction.open.isEnabledFor([folder]), isFalse);
    });

    test('rename applies to one entry of either kind', () {
      expect(FileAction.rename.isEnabledFor([file]), isTrue);
      expect(FileAction.rename.isEnabledFor([folder]), isTrue);
      expect(FileAction.rename.isEnabledFor([file, other]), isFalse);
    });

    test('duplicate covers directories too, via cp -r', () {
      expect(FileAction.duplicate.isEnabledFor([file]), isTrue);
      expect(FileAction.duplicate.isEnabledFor([folder]), isTrue);
      expect(FileAction.duplicate.isEnabledFor([file, other]), isFalse);
    });

    test('properties needs exactly one entry', () {
      expect(FileAction.properties.isEnabledFor([folder]), isTrue);
      expect(FileAction.properties.isEnabledFor([file, other]), isFalse);
    });
  });

  group('multi-selection actions', () {
    test('delete applies to any non-empty selection', () {
      expect(FileAction.delete.isEnabledFor([file, folder]), isTrue);
      expect(FileAction.delete.isEnabledFor([]), isFalse);
    });

    test('download accepts folders, which are walked recursively', () {
      expect(FileAction.download.isEnabledFor([file, other]), isTrue);
      // Mixed selections are fine now that folders expand into per-file jobs.
      expect(FileAction.download.isEnabledFor([file, folder]), isTrue);
      expect(FileAction.download.isEnabledFor([folder]), isTrue);
      expect(FileAction.download.isEnabledFor([]), isFalse);
    });

    test('copyPath applies to any selection', () {
      expect(FileAction.copyPath.isEnabledFor([file, folder]), isTrue);
      expect(FileAction.copyPath.isEnabledFor([]), isFalse);
    });
  });

  group('selection-independent actions', () {
    test('newFolder and refresh are always available', () {
      for (final action in [FileAction.newFolder, FileAction.refresh]) {
        expect(action.isEnabledFor([]), isTrue, reason: action.name);
        expect(action.isEnabledFor([file]), isTrue, reason: action.name);
      }
    });
  });

  group('menu definitions', () {
    test('the row menu covers every action a selection can use', () {
      final inMenu = FileAction.rowMenu.whereType<FileAction>().toSet();
      // newFolder and refresh belong to the background menu instead.
      final expected = FileAction.values.toSet()
        ..removeAll({FileAction.newFolder, FileAction.refresh});
      expect(inMenu, expected);
    });

    test('the background menu offers only selection-free actions', () {
      for (final action in FileAction.backgroundMenu.whereType<FileAction>()) {
        expect(
          action.isEnabledFor([]),
          isTrue,
          reason: '${action.name} would always be disabled on empty space',
        );
      }
    });

    test('every action has a label and description', () {
      for (final action in FileAction.values) {
        expect(action.label, isNotEmpty);
        expect(action.description, isNotEmpty);
      }
    });
  });
}
