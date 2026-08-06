// Live verification of the transfer queue against a connected device.
//
//   flutter test packages/feature_files/test_live/live_transfer_test.dart
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

const _scratch = '/data/local/tmp/adb_transfer_live';

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
    session = AdbSession(await transport.connect(online.first.serial),
        online.first);
    files = FileService(session);
    localTemp = Directory.systemTemp.createTempSync('adb_transfer_live');
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
    // Poll rather than sleeping a fixed amount, so a slow device does not
    // produce a flaky test.
    for (var i = 0; i < 200 && manager.isBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('runs a queue of pushes to completion, one at a time', () async {
    final sources = <String>[];
    for (var i = 0; i < 4; i++) {
      final file = File('${localTemp.path}/q$i.bin')
        ..writeAsBytesSync(List.filled(120000, i));
      sources.add(file.path);
    }

    // Observe how many run concurrently -- the manager must serialise.
    var maxConcurrent = 0;
    manager.addListener(() {
      final running = manager.jobs
          .where((j) => j.state == TransferState.running)
          .length;
      if (running > maxConcurrent) maxConcurrent = running;
    });

    for (var i = 0; i < sources.length; i++) {
      manager.enqueuePush(sources[i], '$_scratch/q$i.bin');
    }
    await settle();

    expect(manager.jobs, hasLength(4));
    expect(
      manager.jobs.every((j) => j.state == TransferState.completed),
      isTrue,
      reason: manager.jobs.map((j) => '${j.name}:${j.state}').join(', '),
    );
    expect(maxConcurrent, 1, reason: 'transfers must not overlap');

    for (var i = 0; i < 4; i++) {
      expect((await files.stat('$_scratch/q$i.bin')).size, 120000);
    }
  });

  test('reports progress and a plausible rate', () async {
    final source = File('${localTemp.path}/rate.bin')
      ..writeAsBytesSync(List.filled(4 * 1024 * 1024, 7));

    final job = manager.enqueuePush(source.path, '$_scratch/rate.bin');
    await settle();

    expect(job.state, TransferState.completed);
    expect(job.bytes, 4 * 1024 * 1024);
    expect(job.fraction, 1.0);
    // ignore: avoid_print
    print('rate: ${job.rate} B/s over ${job.finishedAt!.difference(job.startedAt!).inMilliseconds}ms');
    expect(job.rate, isNotNull);
    expect(job.rate, greaterThan(0));
  });

  test('pull round trips back to disk', () async {
    final source = File('${localTemp.path}/down.bin')
      ..writeAsBytesSync(List.generate(50000, (i) => i % 251));
    await files.push(source.path, '$_scratch/down.bin');

    final dest = '${localTemp.path}/down_back.bin';
    final job = manager.enqueuePull('$_scratch/down.bin', dest);
    await settle();

    expect(job.state, TransferState.completed);
    expect(File(dest).readAsBytesSync(), source.readAsBytesSync());
  });

  test('a failing job does not stall the ones behind it', () async {
    final source = File('${localTemp.path}/ok.bin')..writeAsStringSync('ok');

    // /system is read-only, so this one must fail.
    final bad = manager.enqueuePush(source.path, '/system/nope.bin');
    final good = manager.enqueuePush(source.path, '$_scratch/ok.bin');
    await settle();

    expect(bad.state, TransferState.failed);
    expect(bad.error, isNotNull);
    expect(
      good.state,
      TransferState.completed,
      reason: 'a failure must not abort the rest of the queue',
    );
  });

  test('cancelling a queued job leaves the running one alone', () async {
    final source = File('${localTemp.path}/c.bin')
      ..writeAsBytesSync(List.filled(2 * 1024 * 1024, 3));

    final first = manager.enqueuePush(source.path, '$_scratch/c1.bin');
    final second = manager.enqueuePush(source.path, '$_scratch/c2.bin');
    manager.cancel(second);
    await settle();

    expect(first.state, TransferState.completed);
    expect(second.state, TransferState.cancelled);
    expect((await files.stat('$_scratch/c2.bin')).exists, isFalse);
  });

  test('clearFinished empties the visible list', () async {
    final source = File('${localTemp.path}/cf.bin')..writeAsStringSync('x');
    manager.enqueuePush(source.path, '$_scratch/cf.bin');
    await settle();

    expect(manager.jobs, isNotEmpty);
    manager.clearFinished();
    expect(manager.jobs, isEmpty);
  });
}
