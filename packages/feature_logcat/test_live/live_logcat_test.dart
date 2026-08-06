// Live verification against a physically connected device.
//
// Kept out of `test/` on purpose so CI (which has no device) does not run it.
//
//   flutter test packages/feature_logcat/test_live
@Timeout(Duration(seconds: 90))
library;

import 'package:adb_core/adb_core.dart';
import 'package:feature_logcat/feature_logcat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late LogcatService logcat;

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) {
      fail('No online device. Connect one and enable USB debugging.');
    }
    final device = online.first;
    session = AdbSession(await transport.connect(device.serial), device);
    logcat = LogcatService(session);
    // ignore: avoid_print
    print('device: ${device.displayName} (${device.serial})');
  });

  tearDownAll(() async {
    await session.close();
    await transport.close();
  });

  group('dump', () {
    test('parses the overwhelming majority of real lines', () async {
      final entries = await logcat.dump(tail: 300);
      expect(entries, isNotEmpty);

      final parsed = entries.where((e) => e.isParsed).length;
      final ratio = parsed / entries.length;
      // ignore: avoid_print
      print('parsed $parsed/${entries.length} (${(ratio * 100).round()}%)');

      // Banners and stack traces are legitimately unparsed, but if the format
      // assumption were wrong this would collapse toward zero.
      expect(ratio, greaterThan(0.9));
    });

    test('populates every field from real output', () async {
      final entries = await logcat.dump(tail: 300);
      final entry = entries.firstWhere((e) => e.isParsed);

      expect(entry.pid, isNotNull);
      expect(entry.pid, greaterThan(0));
      expect(entry.tid, isNotNull);
      expect(entry.tag, isNotNull);
      expect(entry.tag, isNotEmpty);
      expect(entry.level, isNotNull);
      expect(entry.timestamp, isNotNull);
    });

    test('timestamps land in the present, not a guessed wrong year', () async {
      // The year modifier should be honoured; if it silently were not, the
      // inferred year could still be right, so also check the date is recent.
      final entries = await logcat.dump(tail: 300);
      final stamped = entries
          .where((e) => e.timestamp != null)
          .map((e) => e.timestamp!)
          .toList();
      expect(stamped, isNotEmpty);

      final now = DateTime.now();
      final newest = stamped.reduce((a, b) => a.isAfter(b) ? a : b);
      expect(newest.year, now.year);
      expect(
        now.difference(newest).inHours.abs(),
        lessThan(48),
        reason: 'newest entry $newest is not close to now',
      );
    });

    test('keeps the buffer banner rather than dropping it', () async {
      final entries = await logcat.dump(tail: 500);
      final banners =
          entries.where((e) => e.raw.contains('beginning of')).toList();
      // Not guaranteed in every window, but when present it must be retained
      // as unparsed rather than silently discarded.
      for (final banner in banners) {
        expect(banner.isParsed, isFalse);
      }
    });

    test('all priority letters seen map to real levels', () async {
      final entries = await logcat.dump(tail: 500);
      final levels = entries
          .where((e) => e.isParsed)
          .map((e) => e.level!)
          .toSet();
      // ignore: avoid_print
      print('levels seen: ${levels.map((l) => l.code).join()}');
      expect(levels, isNotEmpty);
    });
  });

  group('streaming', () {
    test('delivers entries live and reassembles across chunks', () async {
      final received = <LogcatEntry>[];
      final sub = logcat.watch().listen(received.add);

      await Future<void>.delayed(const Duration(seconds: 3));
      await sub.cancel();

      // ignore: avoid_print
      print('streamed ${received.length} entries in 3s');
      expect(received, isNotEmpty);

      // Chunk boundaries land mid-line constantly at this rate. If the line
      // assembler were broken, parsed entries would be badly corrupted.
      final parsed = received.where((e) => e.isParsed).toList();
      expect(parsed, isNotEmpty);
      for (final entry in parsed.take(50)) {
        expect(entry.tag, isNot(contains('\n')));
        expect(entry.pid, greaterThan(0));
      }
    });

    test('a filter applied to real output selects a strict subset', () async {
      final entries = await logcat.dump(tail: 500);
      const filter = LogFilter(
        minLevel: LogLevel.warn,
        includeUnparsed: false,
      );
      final kept = entries.where(filter.matches).toList();

      expect(kept.length, lessThanOrEqualTo(entries.length));
      for (final entry in kept) {
        expect(entry.level!.atLeast(LogLevel.warn), isTrue);
      }
    });
  });

  group('controller', () {
    test('coalesces repaints under real throughput', () async {
      final controller = LogcatController(
        service: logcat,
        capacity: 20000,
        flushInterval: const Duration(milliseconds: 100),
      );

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.start(includeExisting: false);
      await Future<void>.delayed(const Duration(seconds: 3));
      await controller.stop();

      // ignore: avoid_print
      print('${controller.totalCount} entries, $notifications notifications');

      expect(controller.totalCount, greaterThan(0));
      // The whole point of the design: repaints must track the flush interval
      // (~30 in 3s plus a few lifecycle events), not the entry count.
      expect(notifications, lessThan(60));
      expect(notifications, lessThan(controller.totalCount));

      controller.dispose();
    });
  });
}
