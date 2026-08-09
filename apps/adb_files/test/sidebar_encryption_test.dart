import 'package:adb_files/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, bool? encrypted) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Sidebar(deviceName: 'SM-A715F', encrypted: encrypted),
      ),
    ),
  );

  testWidgets('a plaintext session is called out', (tester) async {
    await pump(tester, false);
    expect(find.text('Not encrypted'), findsOneWidget);
  });

  testWidgets('an encrypted session says nothing', (tester) async {
    // Deliberately silent rather than reassuring: a green badge on every
    // secure session trains people to ignore the row the warning appears in.
    await pump(tester, true);
    expect(find.text('Not encrypted'), findsNothing);
  });

  testWidgets('an unknown session says nothing', (tester) async {
    // null is the adb-server case, where we genuinely cannot tell. Warning
    // here would fire on every USB session and teach users to dismiss it.
    await pump(tester, null);
    expect(find.text('Not encrypted'), findsNothing);
  });

  testWidgets('the default is silent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Sidebar(deviceName: 'SM-A715F')),
      ),
    );
    expect(find.text('Not encrypted'), findsNothing);
  });
}
