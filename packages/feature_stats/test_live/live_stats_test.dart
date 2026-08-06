// Live verification against a physically connected device.
//
// Kept out of `test/` on purpose so CI (which has no device) does not run it.
//
//   flutter test packages/feature_stats/test_live
@Timeout(Duration(seconds: 90))
library;

import 'package:adb_core/adb_core.dart';
import 'package:feature_stats/feature_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late StatsService stats;

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) {
      fail('No online device. Connect one and enable USB debugging.');
    }
    final device = online.first;
    session = AdbSession(await transport.connect(device.serial), device);
    stats = StatsService(session);
    // ignore: avoid_print
    print('device: ${device.displayName} (${device.serial})');
  });

  tearDownAll(() async {
    await session.close();
    await transport.close();
  });

  test('first sample has no CPU baseline, second does', () async {
    final first = await stats.sample();
    expect(
      first.cpu.overall,
      isNull,
      reason: 'usage is a delta; there is nothing to diff the first reading '
          'against',
    );

    await Future<void>.delayed(const Duration(milliseconds: 700));
    final second = await stats.sample();

    // ignore: avoid_print
    print('cpu overall: ${second.cpu.overall}');
    expect(second.cpu.overall, isNotNull);
    expect(second.cpu.overall, inInclusiveRange(0.0, 1.0));
  });

  test('reports per-core usage for a real multi-core device', () async {
    await stats.sample();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final sample = await stats.sample();

    // ignore: avoid_print
    print('cores: ${sample.cpu.coreCount}, '
        'per-core: ${sample.cpu.perCore.map((u) => u?.toStringAsFixed(2))}');

    expect(sample.cpu.coreCount, greaterThan(1));
    for (final usage in sample.cpu.perCore) {
      if (usage != null) expect(usage, inInclusiveRange(0.0, 1.0));
    }
  });

  test('memory readings are internally consistent', () async {
    final sample = await stats.sample();
    final memory = sample.memory;

    // ignore: avoid_print
    print('mem total=${memory.total} available=${memory.available} '
        'used=${(memory.usedFraction * 100).round()}%');

    expect(memory.total, greaterThan(0));
    expect(memory.available, greaterThan(0));
    expect(memory.available, lessThanOrEqualTo(memory.total));
    expect(memory.used, memory.total - memory.available);
    expect(memory.usedFraction, inInclusiveRange(0.0, 1.0));
    // A phone with under 512 MB would be implausible; catches a unit mistake
    // such as forgetting the kB -> bytes conversion.
    expect(memory.total, greaterThan(512 * 1024 * 1024));
  });

  test('battery readings are physically plausible', () async {
    final battery = (await stats.sample()).battery;

    // ignore: avoid_print
    print('battery ${battery.level}/${battery.scale} '
        '${battery.temperature}C ${battery.voltage}mV '
        '${battery.status.name}/${battery.health.name}');

    expect(battery.level, inInclusiveRange(0, 100));
    expect(battery.scale, greaterThan(0));
    expect(battery.percent, inInclusiveRange(0.0, 1.0));
    // Tenths-of-a-degree conversion: a raw 293 must read as 29.3, not 293.
    expect(battery.temperature, inInclusiveRange(-20.0, 70.0));
    // Millivolts for a single-cell Li-ion pack.
    expect(battery.voltage, inInclusiveRange(2000, 5000));
    expect(battery.status, isNot(BatteryStatus.unknown));
  });

  test('uptime is positive and advances between samples', () async {
    final first = await stats.sample();
    expect(first.uptime, isNotNull);
    expect(first.uptime!.inSeconds, greaterThan(0));

    await Future<void>.delayed(const Duration(seconds: 2));
    final second = await stats.sample();
    expect(second.uptime!.inMilliseconds,
        greaterThan(first.uptime!.inMilliseconds));
  });

  test('watch() emits repeatedly at roughly the requested interval', () async {
    final samples = <DeviceStats>[];
    final started = DateTime.now();

    final sub = stats.watch(interval: const Duration(milliseconds: 500))
        .listen(samples.add);
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    await sub.cancel();

    final elapsed = DateTime.now().difference(started);
    // ignore: avoid_print
    print('${samples.length} samples in ${elapsed.inMilliseconds}ms');

    expect(samples.length, greaterThanOrEqualTo(3));
    // Ticks are sequential, so a slow device stretches the interval but must
    // never queue overlapping shells and overshoot the count.
    expect(samples.length, lessThanOrEqualTo(7));
  });

  test('resetBaseline discards the previous CPU reading', () async {
    await stats.sample();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect((await stats.sample()).cpu.overall, isNotNull);

    stats.resetBaseline();
    expect((await stats.sample()).cpu.overall, isNull);
  });

  test('a full poll is fast enough for 1 Hz sampling', () async {
    await stats.sample(); // warm the baseline
    final watch = Stopwatch()..start();
    await stats.sample();
    watch.stop();

    // ignore: avoid_print
    print('single batched poll: ${watch.elapsedMilliseconds}ms');
    // One batched shell rather than four separate ones is what keeps this
    // comfortably inside a 1 second tick.
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
