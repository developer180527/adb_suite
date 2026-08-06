// Tab behaviour against a real device (TabsController needs a live
// FileService to build its per-tab browsers).
//
//   flutter test apps/adb_files/test_live
@Timeout(Duration(seconds: 90))
library;

import 'package:adb_core/adb_core.dart';
import 'package:adb_files/state/tabs_controller.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HostTransport transport;
  late AdbSession session;
  late FileService files;

  setUpAll(() async {
    transport = await HostTransport.local();
    final online = (await transport.listDevices()).where((d) => d.isOnline);
    if (online.isEmpty) fail('No online device.');
    session = AdbSession(await transport.connect(online.first.serial), online.first);
    files = FileService(session);
  });

  tearDownAll(() async {
    await session.close();
    await transport.close();
  });

  TabsController make() => TabsController(service: files);

  test('starts with exactly one tab and hides the strip', () {
    final tabs = make();
    expect(tabs.tabs, hasLength(1));
    expect(tabs.activeIndex, 0);
    expect(tabs.hasMultiple, isFalse);
    tabs.dispose();
  });

  test('a new tab inherits the current directory and becomes active', () async {
    final tabs = make();
    await tabs.browser.navigateTo('/sdcard/DCIM');

    tabs.newTab();
    expect(tabs.tabs, hasLength(2));
    expect(tabs.activeIndex, 1);
    // Finder opens a new tab where you already are.
    expect(tabs.browser.path, '/sdcard/DCIM');
    tabs.dispose();
  });

  test('tabs keep independent navigation history', () async {
    final tabs = make();
    await tabs.browser.navigateTo('/sdcard/DCIM');
    tabs.newTab(path: '/sdcard/Download');
    await tabs.browser.load();

    expect(tabs.browser.path, '/sdcard/Download');
    tabs.select(0);
    expect(
      tabs.browser.path,
      '/sdcard/DCIM',
      reason: 'switching tabs must not move the other tab',
    );
    tabs.dispose();
  });

  test('the last tab refuses to close so the window can handle it', () {
    final tabs = make();
    expect(tabs.closeActive(), isFalse);
    expect(tabs.tabs, hasLength(1));
    tabs.dispose();
  });

  test('closing selects a neighbour rather than jumping to the start', () {
    final tabs = make()
      ..newTab(path: '/sdcard/DCIM')
      ..newTab(path: '/sdcard/Download');
    expect(tabs.activeIndex, 2);

    // Close the middle tab while the last is active: the active tab shifts
    // down one index but must remain the same tab.
    final activeId = tabs.active.id;
    tabs.closeTab(1);
    expect(tabs.tabs, hasLength(2));
    expect(tabs.active.id, activeId);
    expect(tabs.activeIndex, 1);
    tabs.dispose();
  });

  test('closing the active last tab falls back to the new last', () {
    final tabs = make()..newTab()..newTab();
    expect(tabs.activeIndex, 2);
    tabs.closeActive();
    expect(tabs.activeIndex, 1);
    expect(tabs.tabs, hasLength(2));
    tabs.dispose();
  });

  test('next and previous wrap around', () {
    final tabs = make()..newTab()..newTab();
    expect(tabs.activeIndex, 2);

    tabs.nextTab();
    expect(tabs.activeIndex, 0, reason: 'wraps past the end');
    tabs.previousTab();
    expect(tabs.activeIndex, 2, reason: 'wraps past the start');
    tabs.dispose();
  });

  test('Cmd+number selects by position, with 9 meaning last', () {
    final tabs = make()..newTab()..newTab()..newTab();
    expect(tabs.tabs, hasLength(4));

    tabs.selectByNumber(2);
    expect(tabs.activeIndex, 1);

    // 9 is always the last tab, however many there are.
    tabs.selectByNumber(9);
    expect(tabs.activeIndex, 3);

    // Out of range is ignored rather than clamping to something surprising.
    tabs.selectByNumber(7);
    expect(tabs.activeIndex, 3);
    tabs.dispose();
  });

  test('titles track the directory each tab is showing', () async {
    final tabs = make();
    expect(tabs.active.title, 'Internal storage');

    await tabs.browser.navigateTo('/sdcard/DCIM');
    expect(tabs.active.title, 'DCIM');

    await tabs.browser.navigateTo('/');
    expect(tabs.active.title, 'Device');
    tabs.dispose();
  });

  test('notifies listeners when a tab navigates, so titles refresh', () async {
    final tabs = make();
    var notifications = 0;
    tabs.addListener(() => notifications++);

    await tabs.browser.navigateTo('/sdcard/DCIM');
    expect(notifications, greaterThan(0));
    tabs.dispose();
  });
}
