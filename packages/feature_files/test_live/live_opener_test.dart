// Live verification of the download-and-open flow against a real device.
//
//   flutter test packages/feature_files/test_live/live_opener_test.dart
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

const _scratch = '/data/local/tmp/adb_opener_live';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late FileService files;
  late FileOpener opener;
  late Directory cache;
  late Directory localTemp;

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) fail('No online device.');
    session = AdbSession(await transport.connect(online.first.serial), online.first);
    files = FileService(session);
    localTemp = Directory.systemTemp.createTempSync('adb_opener_local');
    cache = Directory.systemTemp.createTempSync('adb_opener_cache');
    opener = FileOpener(files, cacheDirectory: cache);
    await files.createDirectory(_scratch);
  });

  tearDownAll(() async {
    await files.delete(_scratch, recursive: true);
    localTemp.deleteSync(recursive: true);
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    await session.close();
    await transport.close();
  });

  Future<AdbFileEntry> put(String name, String content) async {
    final local = File('${localTemp.path}/$name')..writeAsStringSync(content);
    await files.push(local.path, '$_scratch/$name');
    return files.stat('$_scratch/$name');
  }

  test('downloads a file into the cache on first open', () async {
    final entry = await put('hello.txt', 'hello from the device');

    expect(opener.isFresh(entry), isFalse, reason: 'nothing cached yet');

    final file = await opener.ensureLocal(entry);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), 'hello from the device');
    expect(file.path, endsWith('hello.txt'), reason: 'keeps name and extension');
  });

  test('a second open reuses the cache without re-downloading', () async {
    final entry = await put('cached.txt', 'cache me');
    final file = await opener.ensureLocal(entry);
    final firstModified = file.statSync().modified;

    expect(opener.isFresh(entry), isTrue);

    final updates = <TransferProgress>[];
    final again = await opener.ensureLocal(entry, onProgress: updates.add);

    expect(again.path, file.path);
    expect(again.statSync().modified, firstModified);
    // A cache hit reports completion immediately rather than streaming.
    expect(updates, hasLength(1));
    expect(updates.single.isComplete, isTrue);
  });

  test('a changed file on the device invalidates the cache', () async {
    final entry = await put('changing.txt', 'first version');
    await opener.ensureLocal(entry);
    expect(opener.isFresh(entry), isTrue);

    // Rewrite it with different content and a different length.
    final updated = await put('changing.txt', 'second version, longer');
    expect(
      opener.isFresh(updated),
      isFalse,
      reason: 'size changed, so the cached copy is stale',
    );

    final refreshed = await opener.ensureLocal(updated);
    expect(refreshed.readAsStringSync(), 'second version, longer');
  });

  test('files with the same name in different folders do not collide',
      () async {
    await files.createDirectory('$_scratch/one');
    await files.createDirectory('$_scratch/two');

    final a = File('${localTemp.path}/dup.txt')..writeAsStringSync('from one');
    await files.push(a.path, '$_scratch/one/dup.txt');
    final b = File('${localTemp.path}/dup2.txt')..writeAsStringSync('from two');
    await files.push(b.path, '$_scratch/two/dup.txt');

    final first = await opener.ensureLocal(await files.stat('$_scratch/one/dup.txt'));
    final second = await opener.ensureLocal(await files.stat('$_scratch/two/dup.txt'));

    expect(first.path, isNot(second.path));
    expect(first.readAsStringSync(), 'from one');
    expect(second.readAsStringSync(), 'from two');
  });

  test('non-ASCII names survive the cache round trip', () async {
    final entry = await put('写真 🎉.txt', 'unicode cached');
    final file = await opener.ensureLocal(entry);
    expect(file.readAsStringSync(), 'unicode cached');
    expect(file.path, contains('写真'));
  });

  test('opening a directory is rejected rather than half-working', () async {
    final dir = await files.stat(_scratch);
    await expectLater(
      opener.openInDefaultApp(dir),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('cacheSize reflects what was downloaded, and clearCache empties it',
      () async {
    final size = await opener.cacheSize();
    expect(size, greaterThan(0));

    await opener.clearCache();
    expect(await opener.cacheSize(), 0);
  });

  test('hands the cached file to the OS without error', () async {
    // Deliberately does not assert *which* app opens: that is the user's
    // LaunchServices configuration, not this code's business. On this machine
    // .txt is claimed by a third-party editor that is already running, so a
    // "did TextEdit launch?" check would report a false negative.
    //
    // The contract being verified is: the file is cached locally, and the
    // platform launcher accepts it (openLocal throws on a nonzero exit).
    final entry = await put('launch_me.txt', 'opened by adb_files');

    final file = await opener.openInDefaultApp(entry);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), 'opened by adb_files');
  });

  test('openLocal surfaces a failure for a path that cannot be opened',
      () async {
    // Guards the error path: a nonexistent file must raise rather than
    // silently doing nothing.
    await expectLater(
      FileOpener.openLocal('${cache.path}/definitely-not-here.xyz'),
      throwsA(isA<AdbException>()),
    );
  }, skip: !Platform.isMacOS ? 'exit codes differ per platform' : null);
}
