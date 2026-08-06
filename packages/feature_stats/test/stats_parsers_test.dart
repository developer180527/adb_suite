import 'package:feature_stats/feature_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseProcStat', () {
    const sample = '''
cpu  100 20 50 800 30 5 5 0 0 0
cpu0 50 10 25 400 15 2 3 0 0 0
cpu1 50 10 25 400 15 3 2 0 0 0
intr 12345 0 0
ctxt 98765
''';

    test('reads the aggregate and per-core lines', () {
      final snapshots = StatsParsers.parseProcStat(sample);
      expect(snapshots, hasLength(3));
      expect(snapshots.first.name, 'cpu');
      expect(snapshots.first.isAggregate, isTrue);
      expect(snapshots[1].name, 'cpu0');
    });

    test('ignores non-cpu lines', () {
      final snapshots = StatsParsers.parseProcStat(sample);
      expect(snapshots.every((s) => s.name.startsWith('cpu')), isTrue);
    });

    test('counts iowait as idle, not busy', () {
      final cpu = StatsParsers.parseProcStat(sample).first;
      expect(cpu.idleTotal, 830); // idle 800 + iowait 30
      expect(cpu.busyTotal, 180); // 100 + 20 + 50 + 5 + 5
      expect(cpu.total, 1010);
    });

    test('tolerates a short line from an older kernel', () {
      final snapshots = StatsParsers.parseProcStat('cpu  100 20 50 800\n');
      expect(snapshots.single.idle, 800);
      expect(snapshots.single.steal, 0);
    });

    test('skips a malformed line rather than throwing', () {
      expect(StatsParsers.parseProcStat('cpu  bad\ncpu0 1 2 3 4\n'), hasLength(1));
    });
  });

  group('diffCpu', () {
    test('computes usage from the delta between two readings', () {
      final before = StatsParsers.parseProcStat('cpu  100 0 0 900 0 0 0 0\n');
      // +100 busy, +100 idle over the interval => 50%.
      final after = StatsParsers.parseProcStat('cpu  200 0 0 1000 0 0 0 0\n');
      expect(StatsParsers.diffCpu(before, after).overall, closeTo(0.5, 1e-9));
    });

    test('a fully busy interval reads as 100%', () {
      final before = StatsParsers.parseProcStat('cpu  100 0 0 900 0 0 0 0\n');
      final after = StatsParsers.parseProcStat('cpu  300 0 0 900 0 0 0 0\n');
      expect(StatsParsers.diffCpu(before, after).overall, 1.0);
    });

    test('an idle interval reads as 0%', () {
      final before = StatsParsers.parseProcStat('cpu  100 0 0 900 0 0 0 0\n');
      final after = StatsParsers.parseProcStat('cpu  100 0 0 1000 0 0 0 0\n');
      expect(StatsParsers.diffCpu(before, after).overall, 0.0);
    });

    test('identical readings yield null, not a divide by zero', () {
      final snapshot = StatsParsers.parseProcStat('cpu  100 0 0 900 0 0 0 0\n');
      expect(StatsParsers.diffCpu(snapshot, snapshot).overall, isNull);
    });

    test('counters going backwards yield null instead of a bogus value', () {
      // Happens when the device reboots between samples.
      final before = StatsParsers.parseProcStat('cpu  500 0 0 5000 0 0 0 0\n');
      final after = StatsParsers.parseProcStat('cpu  10 0 0 50 0 0 0 0\n');
      expect(StatsParsers.diffCpu(before, after).overall, isNull);
    });

    test('matches cores by name so an offline core is not misattributed', () {
      // cpu0 goes offline; cpu1's counters must not be read as cpu0's.
      final before = StatsParsers.parseProcStat(
        'cpu  200 0 0 1800 0 0 0 0\n'
        'cpu0 100 0 0 900 0 0 0 0\n'
        'cpu1 100 0 0 900 0 0 0 0\n',
      );
      final after = StatsParsers.parseProcStat(
        'cpu  400 0 0 1800 0 0 0 0\n'
        'cpu1 300 0 0 900 0 0 0 0\n',
      );

      final usage = StatsParsers.diffCpu(before, after);
      expect(usage.perCore, hasLength(1));
      expect(usage.perCore.single, 1.0); // cpu1's own delta, not cpu0's
    });

    test('a newly online core has no baseline and reports null', () {
      final before = StatsParsers.parseProcStat('cpu0 100 0 0 900 0 0 0 0\n');
      final after = StatsParsers.parseProcStat(
        'cpu0 200 0 0 1000 0 0 0 0\n'
        'cpu1 50 0 0 50 0 0 0 0\n',
      );
      final usage = StatsParsers.diffCpu(before, after);
      expect(usage.perCore[1], isNull);
    });
  });

  group('parseMemInfo', () {
    const sample = '''
MemTotal:        3810144 kB
MemFree:          123456 kB
MemAvailable:    1500000 kB
Buffers:           45000 kB
Cached:          1000000 kB
SwapTotal:       2000000 kB
SwapFree:        1500000 kB
''';

    test('converts kB to bytes', () {
      final memory = StatsParsers.parseMemInfo(sample);
      expect(memory.total, 3810144 * 1024);
      expect(memory.free, 123456 * 1024);
    });

    test('bases used on available, not free', () {
      final memory = StatsParsers.parseMemInfo(sample);
      // Using `free` here would report ~97% used on a healthy device.
      expect(memory.used, (3810144 - 1500000) * 1024);
      expect(memory.usedFraction, closeTo(0.606, 0.01));
    });

    test('computes swap usage', () {
      final memory = StatsParsers.parseMemInfo(sample);
      expect(memory.swapUsed, 500000 * 1024);
      expect(memory.swapUsedFraction, closeTo(0.25, 1e-9));
    });

    test('approximates MemAvailable when the kernel omits it', () {
      final memory = StatsParsers.parseMemInfo(
        'MemTotal: 1000 kB\nMemFree: 100 kB\n'
        'Buffers: 50 kB\nCached: 200 kB\n',
      );
      expect(memory.available, 350 * 1024);
    });

    test('empty input does not divide by zero', () {
      final memory = StatsParsers.parseMemInfo('');
      expect(memory.total, 0);
      expect(memory.usedFraction, 0);
      expect(memory.swapUsedFraction, 0);
    });
  });

  group('parseBattery', () {
    const sample = '''
Current Battery Service state:
  AC powered: false
  USB powered: true
  Wireless powered: false
  status: 2
  health: 2
  present: true
  level: 85
  scale: 100
  voltage: 4201
  temperature: 320
  technology: Li-ion
''';

    test('parses level, scale, and percentage', () {
      final battery = StatsParsers.parseBattery(sample);
      expect(battery.level, 85);
      expect(battery.scale, 100);
      expect(battery.percent, closeTo(0.85, 1e-9));
    });

    test('converts tenths of a degree to Celsius', () {
      expect(StatsParsers.parseBattery(sample).temperature, 32.0);
    });

    test('maps status and health codes to enums', () {
      final battery = StatsParsers.parseBattery(sample);
      expect(battery.status, BatteryStatus.charging);
      expect(battery.health, BatteryHealth.good);
      expect(battery.isCharging, isTrue);
    });

    test('reads the power source flags', () {
      final battery = StatsParsers.parseBattery(sample);
      expect(battery.usbPowered, isTrue);
      expect(battery.acPowered, isFalse);
      expect(battery.isPlugged, isTrue);
    });

    test('scales microvolt readings down to millivolts', () {
      final battery = StatsParsers.parseBattery('voltage: 4201000\n');
      expect(battery.voltage, 4201);
    });

    test('flags a throttling temperature', () {
      expect(StatsParsers.parseBattery('temperature: 470\n').isHot, isTrue);
      expect(StatsParsers.parseBattery('temperature: 320\n').isHot, isFalse);
    });

    test('an unknown status code degrades to unknown', () {
      expect(
        StatsParsers.parseBattery('status: 99\n').status,
        BatteryStatus.unknown,
      );
    });

    test('a non-100 scale still yields a correct percentage', () {
      final battery = StatsParsers.parseBattery('level: 128\nscale: 255\n');
      expect(battery.percent, closeTo(0.502, 0.01));
    });
  });

  group('parseUptime', () {
    test('reads the first field as seconds', () {
      expect(
        StatsParsers.parseUptime('123456.78 987654.32\n'),
        const Duration(milliseconds: 123456780),
      );
    });

    test('returns null on garbage', () {
      expect(StatsParsers.parseUptime('nonsense'), isNull);
      expect(StatsParsers.parseUptime(''), isNull);
    });
  });
}
