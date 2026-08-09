import 'package:feature_connect/feature_connect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The address screen only appears where no local adb server is possible, so
/// these drive it through the controller's `needsAddress` phase.
void main() {
  late ConnectionController controller;

  setUp(() {
    controller = ConnectionController();
    // initialise() would look for an adb binary; resetToAddress puts the
    // controller into the same phase without touching the filesystem.
    controller.resetToAddress();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ConnectPanel(controller: controller))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the port field starts empty', (tester) async {
    await pump(tester);

    // A prefilled 5555 would be wrong nearly every time, because the Wireless
    // debugging port is reassigned whenever the setting is toggled.
    final port = tester.widget<TextField>(
      find.ancestor(
        of: find.text('Port'),
        matching: find.byType(TextField),
      ),
    );
    expect(port.controller?.text, isEmpty);
  });

  testWidgets('an address with no port refuses to connect', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).first, '192.168.1.109');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    // The safety-critical assertion: a missing port must not quietly fall back
    // to 5555, which would swap the encrypted connection the screen promises
    // for a plaintext one.
    expect(
      find.textContaining('Enter the port from Developer options'),
      findsOneWidget,
    );
    expect(controller.phase, ConnectionPhase.needsAddress);
  });

  testWidgets('a missing address refuses to connect', (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter the device'), findsOneWidget);
    expect(controller.phase, ConnectionPhase.needsAddress);
  });

  testWidgets('a nonsense port refuses to connect', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).first, '192.168.1.109');
    await tester.enterText(find.byType(TextField).at(1), '99999');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Enter the port from Developer options'),
      findsOneWidget,
    );
    expect(controller.phase, ConnectionPhase.needsAddress);
  });

  testWidgets('the encrypted path is what the screen leads with', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('Wireless debugging'), findsWidgets);
    expect(find.textContaining('That connection is encrypted'), findsOneWidget);
    // The plaintext port is still reachable, but only as one-time setup behind
    // a disclosure rather than as the headline instruction.
    expect(find.textContaining('First time with this device?'), findsOneWidget);
  });
}
