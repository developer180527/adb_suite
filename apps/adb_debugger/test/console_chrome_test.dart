import 'package:adb_debugger/widgets/status_bar.dart';
import 'package:adb_debugger/widgets/vitals_rail.dart';
import 'package:feature_logcat/feature_logcat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The console's own chrome. The log body and the stats body are tested in
/// their own packages; what is app-specific is how they are framed.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );

  group('status bar', () {
    late LogcatController controller;

    setUp(() {
      // No device: the controller is inert without start(), which is exactly
      // the state the bar has to render at launch.
      controller = LogcatController(service: _NullLogcatService());
    });

    tearDown(() => controller.dispose());

    testWidgets('reports an empty buffer without a filter count', (
      tester,
    ) async {
      await pump(tester, ConsoleStatusBar(controller: controller));

      expect(tester.takeException(), isNull);
      expect(find.text('0 lines'), findsOneWidget);
      // "0 of 0" would be noise when nothing is filtered.
      expect(find.text('filtered'), findsNothing);
    });

    testWidgets('flags an active filter', (tester) async {
      controller.setFilter(const LogFilter(query: 'boot'));
      await pump(tester, ConsoleStatusBar(controller: controller));

      expect(find.text('filtered'), findsOneWidget);
      expect(find.textContaining('of'), findsOneWidget);
    });
  });

  group('vitals rail', () {
    testWidgets('shows the sampling state before the first reading', (
      tester,
    ) async {
      await pump(
        tester,
        const VitalsRail(stats: null, cpuHistory: []),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Vitals'), findsOneWidget);
    });

    testWidgets('a stats failure does not take the window down', (
      tester,
    ) async {
      // The log is the reason the window is open; /proc parsing is the
      // fragile half and must fail in its own corner.
      await pump(
        tester,
        const VitalsRail(
          stats: null,
          cpuHistory: [],
          error: 'permission denied',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Vitals unavailable'), findsOneWidget);
      expect(find.textContaining('permission denied'), findsOneWidget);
    });
  });
}

/// A service that never emits. [LogcatController] only touches it on `start()`,
/// which these tests do not call.
class _NullLogcatService implements LogcatService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
