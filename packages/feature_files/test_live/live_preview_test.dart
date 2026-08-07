// Live verification of range reads, the trash, and the HTTP bridge.
//
//   flutter test packages/feature_files/test_live/live_preview_test.dart
@Timeout(Duration(seconds: 180))
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

const _scratch = '/data/local/tmp/adb_preview_live';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late FileService files;
  late Directory localTemp;

  /// 3 MB of deterministic bytes, pushed once and reused.
  late Uint8List sample;
  const samplePath = '$_scratch/sample.bin';

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) fail('No online device.');
    session = AdbSession(await transport.connect(online.first.serial), online.first);
    files = FileService(session);
    localTemp = Directory.systemTemp.createTempSync('adb_preview');

    final rng = Random(1234);
    sample = Uint8List.fromList(
      List.generate(3 * 1024 * 1024, (_) => rng.nextInt(256)),
    );
    final local = File('${localTemp.path}/sample.bin')..writeAsBytesSync(sample);
    await files.createDirectory(_scratch);
    await files.push(local.path, samplePath);
  });

  tearDownAll(() async {
    await files.delete(_scratch, recursive: true);
    await files.delete(TrashService.defaultRoot, recursive: true);
    localTemp.deleteSync(recursive: true);
    await session.close();
    await transport.close();
  });

  group('RemoteFile range reads', () {
    late RemoteFile file;

    setUp(() async => file = await RemoteFile.open(session, samplePath));

    test('reports the real size', () {
      expect(file.size, sample.length);
    });

    test('reads a prefix', () async {
      final got = await file.readHead(1024);
      expect(got, sample.sublist(0, 1024));
    });

    test('reads the tail — the ZIP central-directory case', () async {
      final started = DateTime.now();
      final got = await file.readTail(65536);
      final ms = DateTime.now().difference(started).inMilliseconds;
      // ignore: avoid_print
      print('tail 64KB in ${ms}ms');
      expect(got, sample.sublist(sample.length - 65536));
    });

    test('reads an arbitrary unaligned interior range', () async {
      const offset = 1234567;
      const length = 9999;
      final got = await file.read(offset, length);
      expect(got, sample.sublist(offset, offset + length));
    });

    test('reads a block-aligned range via the dd fast path', () async {
      const mb = 1024 * 1024;
      final started = DateTime.now();
      final got = await file.read(mb, mb);
      final ms = DateTime.now().difference(started).inMilliseconds;
      // ignore: avoid_print
      print('1MB aligned in ${ms}ms '
          '(${(1 / (ms / 1000)).toStringAsFixed(1)} MB/s)');
      expect(got, sample.sublist(mb, mb * 2));
    });

    test('clamps a read that runs past the end', () async {
      final got = await file.read(sample.length - 100, 5000);
      expect(got.length, 100);
      expect(got, sample.sublist(sample.length - 100));
    });

    test('reads past the end return empty rather than throwing', () async {
      expect(await file.read(sample.length, 10), isEmpty);
      expect(await file.read(0, 0), isEmpty);
    });

    test('rejects negative arguments', () async {
      expect(() => file.read(-1, 10), throwsArgumentError);
      expect(() => file.read(0, -5), throwsArgumentError);
    });

    test('opening a directory or missing path fails clearly', () async {
      await expectLater(
        RemoteFile.open(session, _scratch),
        throwsArgumentError,
      );
      await expectLater(
        RemoteFile.open(session, '$_scratch/nope.bin'),
        throwsA(isA<AdbFailure>()),
      );
    });

    test('handles a path with shell metacharacters', () async {
      const nasty = '$_scratch/we\$ird; name `x`.bin';
      final local = File('${localTemp.path}/n.bin')
        ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5]));
      await files.push(local.path, nasty);

      final handle = await RemoteFile.open(session, nasty);
      expect(await handle.read(1, 3), [2, 3, 4]);
    });
  });

  group('TrashService', () {
    late TrashService trash;

    setUp(() async {
      trash = TrashService(files);
      await trash.empty();
    });

    Future<AdbFileEntry> put(String name, String content) async {
      final local = File('${localTemp.path}/$name')..writeAsStringSync(content);
      await files.push(local.path, '$_scratch/$name');
      return files.stat('$_scratch/$name');
    }

    test('moving to trash removes the original and records it', () async {
      final entry = await put('doomed.txt', 'bye');
      final item = await trash.moveToTrash(entry);

      expect(await files.exists(entry.path), isFalse);
      expect(item.originalPath, entry.path);
      expect((await trash.list()).map((i) => i.name), contains('doomed.txt'));
    });

    test('restore puts it back with its content intact', () async {
      final entry = await put('restore_me.txt', 'still here');
      final item = await trash.moveToTrash(entry);

      final target = await trash.restore(item);
      expect(target, entry.path);
      expect(await files.readText(entry.path), 'still here');
      expect(await trash.list(), isEmpty);
    });

    test('restoring onto an occupied name does not overwrite', () async {
      final entry = await put('clash.txt', 'original');
      final item = await trash.moveToTrash(entry);
      // Something new takes the old name before the restore.
      await put('clash.txt', 'replacement');

      final target = await trash.restore(item);
      expect(target, isNot(entry.path));
      expect(await files.readText(entry.path), 'replacement');
      expect(await files.readText(target), 'original');
    });

    test('two files with the same name from different folders coexist',
        () async {
      await files.createDirectory('$_scratch/a');
      await files.createDirectory('$_scratch/b');
      final local = File('${localTemp.path}/same.txt');

      local.writeAsStringSync('from a');
      await files.push(local.path, '$_scratch/a/same.txt');
      local.writeAsStringSync('from b');
      await files.push(local.path, '$_scratch/b/same.txt');

      await trash.moveToTrash(await files.stat('$_scratch/a/same.txt'));
      await trash.moveToTrash(await files.stat('$_scratch/b/same.txt'));

      final items = await trash.list();
      expect(items, hasLength(2));
      expect(items.map((i) => i.id).toSet(), hasLength(2));
    });

    test('trashes a folder and restores it whole', () async {
      await files.createDirectory('$_scratch/tree/inner');
      final local = File('${localTemp.path}/leaf.txt')
        ..writeAsStringSync('leaf');
      await files.push(local.path, '$_scratch/tree/inner/leaf.txt');

      final item = await trash.moveToTrash(await files.stat('$_scratch/tree'));
      expect(await files.exists('$_scratch/tree'), isFalse);
      expect(item.isDirectory, isTrue);

      await trash.restore(item);
      expect(await files.readText('$_scratch/tree/inner/leaf.txt'), 'leaf');
    });

    test('a name with shell metacharacters survives the round trip', () async {
      final entry = await put("od'd; rm -rf x.txt", 'quoted safely');
      final item = await trash.moveToTrash(entry);
      await trash.restore(item);
      expect(await files.readText(entry.path), 'quoted safely');
    });

    test('permanent delete and empty clear the trash', () async {
      final item = await trash.moveToTrash(await put('gone.txt', 'x'));
      await trash.deletePermanently(item);
      expect(await trash.list(), isEmpty);

      await trash.moveToTrash(await put('gone2.txt', 'y'));
      await trash.empty();
      expect(await trash.list(), isEmpty);
    });

    test('refuses to trash something already in the trash', () async {
      final item = await trash.moveToTrash(await put('recursive.txt', 'x'));
      final inTrash =
          await files.stat('${TrashService.defaultRoot}/files/${item.id}');
      await expectLater(
        trash.moveToTrash(inTrash),
        throwsArgumentError,
      );
    });
  });

  group('RemoteFileServer', () {
    late RemoteFileServer server;
    late HttpClient client;
    late Uri url;

    setUpAll(() async {
      server = RemoteFileServer(session);
      client = HttpClient();
      url = await server.publish(samplePath);
      // ignore: avoid_print
      print('serving at $url');
    });

    tearDownAll(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<HttpClientResponse> get(String? range, {String method = 'GET'}) async {
      final request = await client.openUrl(method, url);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      return request.close();
    }

    test('binds to loopback only', () {
      expect(url.host, '127.0.0.1');
      expect(server.isRunning, isTrue);
    });

    test('HEAD reports the size and advertises range support', () async {
      final response = await get(null, method: 'HEAD');
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentLength, sample.length);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      await response.drain<void>();
    });

    test('a ranged GET returns 206 with the right bytes', () async {
      final response = await get('bytes=1000-1999');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 1000-1999/${sample.length}',
      );

      final body = await _collect(response);
      expect(body.length, 1000);
      expect(body, sample.sublist(1000, 2000));
    });

    test('an open-ended range runs to the end of the file', () async {
      final start = sample.length - 500;
      final response = await get('bytes=$start-');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(await _collect(response), sample.sublist(start));
    });

    test('a suffix range returns the last N bytes', () async {
      // `bytes=-500` means the final 500 bytes, not the first 500.
      final response = await get('bytes=-500');
      final body = await _collect(response);
      expect(body, sample.sublist(sample.length - 500));
    });

    test('an unsatisfiable range gets 416', () async {
      final response = await get('bytes=${sample.length + 10}-');
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      await response.drain<void>();
    });

    test('a bad token is rejected', () async {
      final tampered = url.replace(
        pathSegments: ['deadbeef', ...url.pathSegments.skip(1)],
      );
      final response = await (await client.getUrl(tampered)).close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    });

    test('an unknown handle is rejected', () async {
      final tampered = url.replace(
        pathSegments: [url.pathSegments[0], '9999', 'x.bin'],
      );
      final response = await (await client.getUrl(tampered)).close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    });

    test('sets a media content type from the extension', () async {
      final videoPath = '$_scratch/clip.mp4';
      final local = File('${localTemp.path}/clip.mp4')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(2048, 7)));
      await files.push(local.path, videoPath);

      final videoUrl = await server.publish(videoPath);
      final response = await (await client.getUrl(videoUrl)).close();
      expect(response.headers.contentType?.mimeType, 'video/mp4');
      await response.drain<void>();
    });

    test('publishing the same path twice reuses the handle', () async {
      final again = await server.publish(samplePath);
      expect(again, url);
    });

    test('scattered seeks return correct bytes, as a player would', () async {
      // Simulates scrubbing: jump around and verify every window.
      for (final start in [0, 500000, 2000000, sample.length - 4096]) {
        final response = await get('bytes=$start-${start + 4095}');
        final body = await _collect(response);
        final want = sample.sublist(start, min(start + 4096, sample.length));
        expect(body, want, reason: 'window at $start');
      }
    });

    test('a full GET streams the whole file intact', () async {
      final started = DateTime.now();
      final response = await get(null);
      expect(response.statusCode, HttpStatus.ok);
      final body = await _collect(response);
      final ms = DateTime.now().difference(started).inMilliseconds;
      // ignore: avoid_print
      print('full 3MB stream in ${ms}ms '
          '(${(3 / (ms / 1000)).toStringAsFixed(1)} MB/s)');
      expect(body.length, sample.length);
      expect(body, sample);
    });
  });

  group('PreviewController', () {
    late RemoteFileServer server;

    setUpAll(() async => server = RemoteFileServer(session));
    tearDownAll(() async => server.stop());

    Future<PreviewController> previewOf(String name, {String? content}) async {
      final local = File('${localTemp.path}/$name');
      if (content != null) {
        local.writeAsStringSync(content);
      } else {
        local.writeAsBytesSync(sample.sublist(0, 4096));
      }
      await files.push(local.path, '$_scratch/$name');
      final entry = await files.stat('$_scratch/$name');
      final controller = PreviewController(
        session: session,
        server: server,
        entry: entry,
      );
      await controller.load();
      return controller;
    }

    test('text loads a window without pulling the whole file', () async {
      final big = StringBuffer();
      for (var i = 0; i < 20000; i++) {
        big.writeln('line $i padded out to make this file large enough');
      }
      final controller = await previewOf('big.log', content: big.toString());

      expect(controller.kind, PreviewKind.text);
      expect(controller.error, isNull);
      expect(controller.text, isNotNull);
      expect(controller.isTruncated, isTrue,
          reason: 'the file is larger than the preview window');
      expect(controller.text!.length, lessThan(controller.size));
      expect(controller.text, startsWith('line 0'));
      controller.dispose();
    });

    test('load all fetches the rest on request', () async {
      final big = StringBuffer();
      for (var i = 0; i < 20000; i++) {
        big.writeln('line $i padded out to make this file large enough');
      }
      final controller = await previewOf('big2.log', content: big.toString());
      expect(controller.isTruncated, isTrue);

      await controller.loadFullText();
      expect(controller.isTruncated, isFalse);
      expect(controller.text, contains('line 19999'));
      controller.dispose();
    });

    test('a small text file is not marked truncated', () async {
      final controller = await previewOf('small.txt', content: 'hello');
      expect(controller.isTruncated, isFalse);
      expect(controller.text, 'hello');
      controller.dispose();
    });

    test('binary falls back to a hex page and can page through', () async {
      final controller = await previewOf('blob.img');
      expect(controller.kind, PreviewKind.binary);
      expect(controller.hexBytes, isNotNull);
      expect(controller.hexOffset, 0);
      expect(controller.canPageBack, isFalse);

      if (controller.canPageForward) {
        await controller.hexNext();
        expect(controller.hexOffset, greaterThan(0));
        expect(controller.canPageBack, isTrue);
      }
      controller.dispose();
    });

    test('an image publishes a streaming URL rather than downloading',
        () async {
      final local = File('${localTemp.path}/pic.png')
        ..writeAsBytesSync(sample.sublist(0, 8192));
      await files.push(local.path, '$_scratch/pic.png');
      final entry = await files.stat('$_scratch/pic.png');

      final controller = PreviewController(
        session: session, server: server, entry: entry);
      await controller.load();

      expect(controller.kind, PreviewKind.image);
      expect(controller.url, isNotNull);
      expect(controller.url!.host, '127.0.0.1');
      controller.dispose();
    });

    test('disposing revokes the URL so a closed tab stops serving', () async {
      final local = File('${localTemp.path}/gone.png')
        ..writeAsBytesSync(sample.sublist(0, 1024));
      await files.push(local.path, '$_scratch/gone.png');
      final entry = await files.stat('$_scratch/gone.png');

      final controller = PreviewController(
        session: session, server: server, entry: entry);
      await controller.load();
      final url = controller.url!;
      controller.dispose();

      final client = HttpClient();
      final response = await (await client.getUrl(url)).close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
      client.close();
    });

    test('a missing file surfaces an error instead of hanging', () async {
      final controller = PreviewController(
        session: session,
        server: server,
        entry: await files.stat('$_scratch/not_here.txt'),
      );
      await controller.load();
      expect(controller.error, isNotNull);
      controller.dispose();
    });

    test('a document fetches a local copy for the platform renderer',
        () async {
      // Word/Excel/PDF renderers need a real path; only these kinds pay the
      // download cost, and only because no renderer can stream them.
      final local = File('${localTemp.path}/report.rtf')
        ..writeAsStringSync(r'{\rtf1\ansi Hello}');
      await files.push(local.path, '$_scratch/report.rtf');
      final entry = await files.stat('$_scratch/report.rtf');

      final opener = FileOpener(
        files,
        cacheDirectory: Directory('${localTemp.path}/cache'),
      );
      final controller = PreviewController(
        session: session,
        server: server,
        entry: entry,
        opener: opener,
      );
      await controller.load();

      expect(controller.kind, PreviewKind.document);
      expect(controller.error, isNull);
      expect(controller.localFile, isNotNull);
      expect(controller.localFile!.existsSync(), isTrue);
      expect(controller.localFile!.readAsStringSync(), contains('Hello'));
      controller.dispose();
    });

    test('without an opener a document still gets a streaming URL', () async {
      final local = File('${localTemp.path}/nofetch.rtf')
        ..writeAsStringSync(r'{\rtf1\ansi X}');
      await files.push(local.path, '$_scratch/nofetch.rtf');
      final entry = await files.stat('$_scratch/nofetch.rtf');

      final controller = PreviewController(
        session: session, server: server, entry: entry);
      await controller.load();

      expect(controller.localFile, isNull);
      expect(controller.url, isNotNull);
      controller.dispose();
    });
  });
}

Future<Uint8List> _collect(HttpClientResponse response) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.toBytes();
}
