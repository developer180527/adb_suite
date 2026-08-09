import 'package:feature_stats/feature_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// This file exists because the panel shipped for months without ever being
/// mounted. Every test in this package was a parser test, so a layout bug that
/// blanked the entire widget survived until a second app tried to use it.
void main() {
  DeviceStats sample({Duration? uptime, bool swap = false}) => DeviceStats(
    sampledAt: DateTime.now(),
    cpu: const CpuUsage(overall: 0.32, perCore: [0.4, 0.2, null, 0.9]),
    memory: MemoryStats(
      total: 8000000000,
      free: 1000000000,
      available: 3000000000,
      buffers: 500000000,
      cached: 2000000000,
      swapTotal: swap ? 2000000000 : 0,
      swapFree: swap ? 1000000000 : 0,
    ),
    battery: const BatteryStats(
      level: 62,
      scale: 100,
      status: BatteryStatus.discharging,
      health: BatteryHealth.good,
      temperature: 31.4,
      voltage: 4123,
      acPowered: false,
      usbPowered: false,
    ),
    uptime: uptime,
  );

  Future<void> pump(
    WidgetTester tester,
    DeviceStats? stats, {
    List<double> history = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // A narrow, scrollable column is the real usage: a fixed-width rail
          // beside a log. It is also the constraint the old layout could not
          // survive, so the width is deliberate.
          body: SizedBox(
            width: 268,
            child: StatsPanel(stats: stats, cpuHistory: history),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders without a layout exception', (tester) async {
    // Uptime present is the case that used to throw: the panel renders a tile
    // directly in its scrolling Column, and the tile carried its own Expanded.
    await pump(tester, sample(uptime: const Duration(days: 6, hours: 17)));

    expect(tester.takeException(), isNull);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('Uptime'), findsOneWidget);
  });

  testWidgets('renders with a CPU history', (tester) async {
    await pump(
      tester,
      sample(uptime: const Duration(hours: 3)),
      history: List.generate(60, (i) => (i % 20) / 20),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without uptime', (tester) async {
    await pump(tester, sample());
    expect(tester.takeException(), isNull);
    expect(find.text('Uptime'), findsNothing);
  });

  testWidgets('renders with swap present', (tester) async {
    await pump(tester, sample(swap: true, uptime: const Duration(minutes: 5)));
    expect(tester.takeException(), isNull);
    expect(find.text('Swap'), findsOneWidget);
  });

  testWidgets('shows a spinner before the first sample', (tester) async {
    await pump(tester, null);
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
