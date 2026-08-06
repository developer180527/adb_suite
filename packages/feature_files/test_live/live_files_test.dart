// Live verification against a physically connected device.
//
// All writes are confined to a scratch directory under /data/local/tmp, which
// is removed in tearDownAll.
//
//   flutter test packages/feature_files/test_live
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

const _scratch = '/data/local/tmp/adb_files_live';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late FileService files;
  late Directory localTemp;

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) {
      fail('No online device. Connect one and enable USB debugging.');
    }
    final device = online.first;
    session = AdbSession(await transport.connect(device.serial), device);
    files = FileService(session);
    localTemp = Directory.systemTemp.createTempSync('adb_files_live');

    await files.createDirectory(_scratch);
    // ignore: avoid_print
    print('device: ${device.displayName} (${device.serial})');
  });

  tearDownAll(() async {
    await files.delete(_scratch, recursive: true);
    localTemp.deleteSync(recursive: true);
    await session.close();
    await transport.close();
  });

  group('listing distinguishes the empty-looking cases', () {
    test('a readable directory returns contents', () async {
      final listing = await files.list('/sdcard');
      expect(listing, isA<DirectoryContents>());
      final contents = listing as DirectoryContents;
      // ignore: avoid_print
      print('/sdcard: ${contents.entries.length} entries');
      expect(contents.entries, isNotEmpty);
    });

    test('an unreadable directory reports denied, not empty', () async {
      // The whole reason DirectoryListing exists: the sync protocol returns
      // an empty LIST here, indistinguishable from a genuinely empty folder.
      final listing = await files.list('/data/data');
      // ignore: avoid_print
      print('/data/data -> ${listing.runtimeType}');
      expect(listing, isA<DirectoryDenied>());
    });

    test('a genuinely empty directory reports empty contents', () async {
      final empty = '$_scratch/empty_dir';
      await files.createDirectory(empty);
      final listing = await files.list(empty);
      expect(listing, isA<DirectoryContents>());
      expect((listing as DirectoryContents).isEmpty, isTrue);
    });

    test('a missing path reports missing', () async {
      final listing = await files.list('$_scratch/no_such_dir_here');
      expect(listing, isA<DirectoryMissing>());
    });

    test('a file reports not-a-directory', () async {
      final local = File('${localTemp.path}/plain.txt')
        ..writeAsStringSync('hello');
      final remote = '$_scratch/plain.txt';
      await files.push(local.path, remote);

      final listing = await files.list(remote);
      expect(listing, isA<DirectoryNotADirectory>());
    });
  });

  group('hostile filenames', () {
    // Names that would break or execute if quoting were wrong.
    //
    // No slashes: `/` is the one byte a POSIX filename genuinely cannot
    // contain, so including it would just create nested directories and test
    // nothing. Everything else here is a legal filename.
    const names = [
      'with space.txt',
      "it's mine.txt",
      r'$(id).txt',
      '; echo pwned.txt',
      '`id`.txt',
      r'${HOME}.txt',
      'star*.txt',
      'quest?.txt',
      '#hash.txt',
      '&& echo x.txt',
      'pipe | test.txt',
      '写真 🎉.jpg',
      '--looks-like-a-flag',
      'new\tline.txt',
    ];

    test('create, list, and delete each without collateral damage', () async {
      final dir = '$_scratch/hostile';
      await files.createDirectory(dir);

      final local = File('${localTemp.path}/payload.txt')
        ..writeAsStringSync('safe');

      for (final name in names) {
        await files.push(local.path, RemotePath.join(dir, name));
      }

      final listing = await files.list(dir) as DirectoryContents;
      // ignore: avoid_print
      print('created ${listing.entries.length}/${names.length} hostile names');
      for (final name in names) {
        expect(
          listing.entries.any((e) => e.name == name),
          isTrue,
          reason: 'missing "$name" from listing',
        );
      }

      // Every name came back byte-identical, which is itself the security
      // assertion: had `$(id)` or `` `id` `` been evaluated, or `*` expanded,
      // the resulting name would differ from the literal one.
      expect(listing.entries.length, names.length);

      // Delete one at a time and confirm only that one goes.
      var remaining = names.length;
      for (final name in names) {
        await files.delete(RemotePath.join(dir, name));
        remaining--;
        final after = await files.list(dir) as DirectoryContents;
        expect(
          after.entries.length,
          remaining,
          reason: 'deleting "$name" removed the wrong number of files',
        );
      }
    });

    test('a hostile directory name survives a recursive delete', () async {
      // Again no slashes -- the danger is the quote and the semicolon.
      final dir = RemotePath.join(_scratch, "evil'; rm -rf ~");
      await files.createDirectory(dir);

      final local = File('${localTemp.path}/inner.txt')
        ..writeAsStringSync('x');
      await files.push(local.path, RemotePath.join(dir, 'inner.txt'));

      await files.delete(dir, recursive: true);
      expect((await files.stat(dir)).exists, isFalse);

      // /sdcard must still be intact.
      final sdcard = await files.list('/sdcard') as DirectoryContents;
      expect(sdcard.entries, isNotEmpty);
    });
  });

  group('file operations', () {
    test('mkdir, rename, and delete round trip', () async {
      final dir = '$_scratch/ops';
      await files.createDirectory(dir);
      expect((await files.stat(dir)).isDirectory, isTrue);

      final local = File('${localTemp.path}/r.txt')..writeAsStringSync('data');
      await files.push(local.path, '$dir/original.txt');

      await files.rename('$dir/original.txt', 'renamed.txt');
      expect((await files.stat('$dir/original.txt')).exists, isFalse);
      expect((await files.stat('$dir/renamed.txt')).exists, isTrue);

      await files.delete('$dir/renamed.txt');
      expect((await files.stat('$dir/renamed.txt')).exists, isFalse);
    });

    test('rename rejects a path separator in the new name', () async {
      expect(
        () => files.rename('$_scratch/x', 'a/b'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleting the filesystem root is refused outright', () async {
      expect(
        () => files.delete('/', recursive: true),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('copy duplicates a file', () async {
      final dir = '$_scratch/copy';
      await files.createDirectory(dir);
      final local = File('${localTemp.path}/c.txt')
        ..writeAsStringSync('copy me');
      await files.push(local.path, '$dir/a.txt');

      await files.copy('$dir/a.txt', '$dir/b.txt');
      expect((await files.stat('$dir/b.txt')).exists, isTrue);
      expect((await files.stat('$dir/a.txt')).exists, isTrue);
    });

    test('writing somewhere forbidden surfaces an error', () async {
      final local = File('${localTemp.path}/nope.txt')..writeAsStringSync('x');
      await expectLater(
        files.push(local.path, '/system/nope.txt'),
        throwsA(isA<AdbException>()),
      );
    });
  });

  group('transfers', () {
    test('push then pull returns identical bytes', () async {
      final source = File('${localTemp.path}/round.bin')
        ..writeAsBytesSync(List.generate(300000, (i) => i % 256));
      final remote = '$_scratch/round.bin';

      final pushed = <TransferProgress>[];
      await files.push(source.path, remote, onProgress: pushed.add);

      final back = '${localTemp.path}/round_back.bin';
      final pulled = <TransferProgress>[];
      await files.pull(remote, back, onProgress: pulled.add);

      expect(File(back).readAsBytesSync(), source.readAsBytesSync());
      expect(pushed.last.isComplete, isTrue);
      expect(pulled.last.total, source.lengthSync());
    });

    test('a non-ASCII filename transfers both ways', () async {
      final source = File('${localTemp.path}/u.txt')
        ..writeAsStringSync('unicode payload');
      final remote = RemotePath.join(_scratch, '写真 🎉.txt');

      await files.push(source.path, remote);
      final back = '${localTemp.path}/u_back.txt';
      await files.pull(remote, back);

      expect(File(back).readAsStringSync(), 'unicode payload');
    });
  });

  group('space reporting', () {
    test('directorySize returns a plausible total', () async {
      final size = await files.directorySize(_scratch);
      // ignore: avoid_print
      print('scratch size: $size bytes');
      expect(size, isNotNull);
      expect(size, greaterThan(0));
    });

    test('freeSpace reports available under total', () async {
      final space = await files.freeSpace('/sdcard');
      // ignore: avoid_print
      print('sdcard: ${space?.available} free of ${space?.total}');
      expect(space, isNotNull);
      expect(space!.available, greaterThan(0));
      expect(space.available, lessThanOrEqualTo(space.total));
    });
  });

  group('browser controller', () {
    test('navigates, goes up, and tracks history', () async {
      final controller = FileBrowserController(
        service: files,
        initialPath: '/sdcard',
      );
      await controller.load();
      expect(controller.entries, isNotEmpty);

      await controller.navigateTo('/sdcard/DCIM');
      expect(controller.path, '/sdcard/DCIM');
      expect(controller.canGoBack, isTrue);

      await controller.goBack();
      expect(controller.path, '/sdcard');
      expect(controller.canGoForward, isTrue);

      await controller.goUp();
      expect(controller.path, '/');

      controller.dispose();
    });

    test('hidden files are filtered until enabled', () async {
      final controller = FileBrowserController(
        service: files,
        initialPath: '/sdcard',
      );
      await controller.load();

      final visible = controller.entries.length;
      controller.setShowHidden(true);
      final all = controller.entries.length;

      // ignore: avoid_print
      print('/sdcard: $visible visible, $all with hidden');
      expect(all, greaterThanOrEqualTo(visible));
      expect(controller.entries.any((e) => e.isHidden) || all == visible,
          isTrue);

      controller.dispose();
    });

    test('a denied directory yields no entries and keeps the reason',
        () async {
      final controller = FileBrowserController(
        service: files,
        initialPath: '/data/data',
      );
      await controller.load();

      expect(controller.entries, isEmpty);
      expect(controller.listing, isA<DirectoryDenied>());

      controller.dispose();
    });
  });
}
