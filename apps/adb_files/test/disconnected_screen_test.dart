import 'package:adb_files/screens/disconnected_screen.dart';
import 'package:adb_files/state/connection_controller.dart';
import 'package:adb_files/widgets/browser_toolbar.dart';
import 'package:adb_files/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, ConnectionController controller) =>
      tester.pumpWidget(
        MaterialApp(home: DisconnectedScreen(controller: controller)),
      );

  group('the disconnected window keeps the app chrome', () {
    testWidgets('shows the sidebar, toolbar and tab strip', (tester) async {
      await pump(tester, ConnectionController());

      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.byType(BrowserToolbar), findsOneWidget);
      // The shortcuts are the point: the window keeps its shape rather than
      // collapsing to a bare message.
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Internal storage'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
    });

    testWidgets('every toolbar button is disabled', (tester) async {
      await pump(tester, ConnectionController());

      final buttons = tester.widgetList<IconButton>(
        find.descendant(
          of: find.byType(BrowserToolbar),
          matching: find.byType(IconButton),
        ),
      );
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.onPressed, isNull);
      }
    });

    testWidgets('sidebar shortcuts do not navigate', (tester) async {
      await pump(tester, ConnectionController());

      // A shortcut with no controller must not be tappable — reaching through
      // to a null FileBrowserController would throw.
      final inkWells = tester.widgetList<InkWell>(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWells, isNotEmpty);
      for (final well in inkWells) {
        expect(well.onTap, isNull);
      }
    });

    testWidgets('tapping a disabled shortcut is harmless', (tester) async {
      await pump(tester, ConnectionController());

      await tester.tap(find.text('Camera'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('the warning sits inside the skeleton', () {
    testWidgets('the connect message is shown in the content area', (
      tester,
    ) async {
      final controller = ConnectionController();
      await pump(tester, controller);

      // `starting` is the initial phase before any adb discovery runs.
      expect(controller.phase, ConnectionPhase.starting);
      expect(find.text('Starting adb…'), findsOneWidget);
      // …and the chrome is still there alongside it.
      expect(find.byType(Sidebar), findsOneWidget);
    });
  });
}
