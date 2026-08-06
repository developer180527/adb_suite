// Live verification of recursive directory transfer.
//
//   flutter test packages/feature_files/test_live/live_recursive_test.dart
@Timeout(Duration(seconds: 180))
library;

import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

const _scratch = '/data/local/tmp/adb_recursive_live';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late FileService files;
  late TransferManager manager;
  late Directory localTemp;

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) fail('No online device.');
    session = AdbSession(await transport.connect(online.first.serial), online.first);
    files = FileService(session);
    localTemp = Directory.systemTemp.createTempSync('adb_recursive');
    await files.createDirectory(_scratch);
  });

  setUp(() => manager = TransferManager(files));
  tearDown(() => manager.dispose());

  tearDownAll(() async {
    await files.delete(_scratch, recursive: true);
    localTemp.deleteSync(recursive: true);
    await session.close();
    await transport.close();
  });

  Future<void> settle() async {
    for (var i = 0; i < 600 && manager.isBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Builds a nested tree on the device.
  Future<String> buildTree(String name) async {
    final root = '$_scratch/$name';
    await files.createDirectory('$root/a/deep/deeper');
    await files.createDirectory('$root/b');
    await files.createDirectory('$root/empty');

    final local = File('${localTemp.path}/seed.txt');
    for (final entry in {
      '$root/top.txt': 'top level',
      '$root/a/one.txt': 'in a',
      '$root/a/deep/two.txt': 'in a/deep',
      '$root/a/deep/deeper/three.txt': 'in a/deep/deeper',
      '$root/b/four.txt': 'in b',
    }.entries) {
      local.writeAsStringSync(entry.value);
      await files.push(local.path, entry.key);
    }
    return root;
  }

  group('walkDirectory', () {
    test('finds every file at every depth', () async {
      final root = await buildTree('walk');
      final walk = await files.walkDirectory(root);

      expect(walk.fileCount, 5);
      expect(
        walk.files.map((f) => f.relativePath).toSet(),
        {
          'top.txt',
          'a/one.txt',
          'a/deep/two.txt',
          'a/deep/deeper/three.txt',
          'b/four.txt',
        },
      );
      expect(walk.isComplete, isTrue);
    });

    test('records empty directories so they can be recreated', () async {
      final root = await buildTree('empties');
      final walk = await files.walkDirectory(root);
      expect(walk.directories, contains('empty'));
    });

    test('does not follow symlinks, and records them', () async {
      final root = await buildTree('links');
      // A self-referential link: following it would recurse forever.
      await session.shell.run("ln -s '$root' '$root/loop'");

      final walk = await files.walkDirectory(root)
          .timeout(const Duration(seconds: 45));

      // ignore: avoid_print
      print('unsupported: ${walk.unsupported}');
      expect(walk.fileCount, 5, reason: 'the loop must not duplicate files');
      // LIS2 reports the link as mode 0 / unknown rather than S_IFLNK, so it
      // is caught by the "not a regular file" branch rather than isSymlink.
      // Either way it must be visible, not silently dropped.
      expect(walk.unsupported, isNotEmpty);
      expect(walk.unsupported.single, endsWith('/loop'));
    });

    test('a listing never includes . or .., which would loop forever',
        () async {
      // The sync protocol does return these; FileService.list filters them.
      // If that filter regressed, the walk below would not terminate.
      final root = await buildTree('dotdirs');
      final listing = await files.list(root) as DirectoryContents;
      expect(listing.entries.map((e) => e.name), isNot(contains('.')));
      expect(listing.entries.map((e) => e.name), isNot(contains('..')));

      final walk =
          await files.walkDirectory(root).timeout(const Duration(seconds: 30));
      expect(walk.fileCount, 5);
    });

    test('reports unreadable subtrees instead of silently omitting them',
        () async {
      final walk = await files.walkDirectory('/data');
      // /data contains plenty the shell user cannot read.
      // ignore: avoid_print
      print('skipped ${walk.skipped.length} unreadable dirs under /data');
      expect(walk.skipped, isNotEmpty);
      expect(walk.isComplete, isFalse);
    });

    test('honours the file limit and marks the result truncated', () async {
      final root = await buildTree('limited');
      final walk = await files.walkDirectory(
        root,
        limits: const WalkLimits(maxFiles: 2),
      );
      expect(walk.fileCount, 2);
      expect(walk.truncated, isTrue);
      expect(walk.isComplete, isFalse);
    });

    test('honours the depth limit', () async {
      final root = await buildTree('depth');
      final walk = await files.walkDirectory(
        root,
        limits: const WalkLimits(maxDepth: 1),
      );
      expect(walk.truncated, isTrue);
      // top.txt is at depth 0; anything deeper is cut off.
      expect(walk.files.map((f) => f.relativePath), contains('top.txt'));
    });
  });

  group('recursive pull', () {
    test('reproduces the whole tree locally, including empty folders',
        () async {
      final root = await buildTree('pulltree');
      final destination = Directory('${localTemp.path}/out')..createSync();

      final walk = await manager.enqueueDirectoryPull(root, destination.path);
      await settle();

      expect(walk.fileCount, 5);
      expect(
        manager.jobs.every((j) => j.state == TransferState.completed),
        isTrue,
        reason: manager.jobs
            .where((j) => j.state != TransferState.completed)
            .map((j) => '${j.name}:${j.state}:${j.error}')
            .join(', '),
      );

      final base = '${destination.path}/pulltree';
      expect(File('$base/top.txt').readAsStringSync(), 'top level');
      expect(File('$base/a/one.txt').readAsStringSync(), 'in a');
      expect(
        File('$base/a/deep/deeper/three.txt').readAsStringSync(),
        'in a/deep/deeper',
      );
      expect(File('$base/b/four.txt').readAsStringSync(), 'in b');
      expect(
        Directory('$base/empty').existsSync(),
        isTrue,
        reason: 'empty directories must be recreated, not dropped',
      );
    });
  });

  group('recursive push', () {
    test('uploads a local tree and preserves its structure', () async {
      final source = Directory('${localTemp.path}/upload')..createSync();
      Directory('${source.path}/nested/deep').createSync(recursive: true);
      Directory('${source.path}/blank').createSync();
      File('${source.path}/root.txt').writeAsStringSync('root file');
      File('${source.path}/nested/mid.txt').writeAsStringSync('mid file');
      File('${source.path}/nested/deep/leaf.txt').writeAsStringSync('leaf file');

      final count = await manager.enqueueDirectoryPush(source.path, _scratch);
      await settle();

      expect(count, 3);
      expect(
        manager.jobs.every((j) => j.state == TransferState.completed),
        isTrue,
      );

      const base = '$_scratch/upload';
      expect((await files.stat('$base/root.txt')).exists, isTrue);
      expect((await files.stat('$base/nested/mid.txt')).exists, isTrue);
      expect((await files.stat('$base/nested/deep/leaf.txt')).exists, isTrue);
      expect(
        (await files.stat('$base/blank')).isDirectory,
        isTrue,
        reason: 'empty local directories must be created remotely',
      );
    });

    test('a round trip through the device preserves contents', () async {
      final source = Directory('${localTemp.path}/rt')..createSync();
      Directory('${source.path}/sub').createSync();
      File('${source.path}/a.txt').writeAsStringSync('alpha');
      File('${source.path}/sub/b.txt').writeAsStringSync('beta');

      await manager.enqueueDirectoryPush(source.path, _scratch);
      await settle();

      final back = Directory('${localTemp.path}/rtback')..createSync();
      await manager.enqueueDirectoryPull('$_scratch/rt', back.path);
      await settle();

      expect(File('${back.path}/rt/a.txt').readAsStringSync(), 'alpha');
      expect(File('${back.path}/rt/sub/b.txt').readAsStringSync(), 'beta');
    });

    test('non-ASCII names survive a recursive round trip', () async {
      final source = Directory('${localTemp.path}/unicode')..createSync();
      Directory('${source.path}/写真').createSync();
      File('${source.path}/写真/café 🎉.txt').writeAsStringSync('unicode tree');

      await manager.enqueueDirectoryPush(source.path, _scratch);
      await settle();

      expect(
        manager.jobs.every((j) => j.state == TransferState.completed),
        isTrue,
        reason: manager.jobs.map((j) => '${j.name}:${j.error}').join(', '),
      );
      expect(
        (await files.stat('$_scratch/unicode/写真/café 🎉.txt')).exists,
        isTrue,
      );
    });
  });
}
