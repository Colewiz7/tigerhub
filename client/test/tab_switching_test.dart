/// Switching tabs, including out of Customize.
///
/// Cole reported the app glitching when leaving Customize for another page,
/// and general trouble switching pages. The subscription leak explains part of
/// it, but a leak does not throw, so this drives the actual interaction and
/// fails on any framework exception rather than trusting that it is fine.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/page_veil.dart';

/// Answers every path with an empty but well formed envelope, so the shell
/// builds its real widget tree without touching the network.
class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<SchemeController> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 950);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();

    await tester.pumpWidget(MaterialApp(
      home: AppShell(api: ApiClient(backend: _EmptyBackend()), scheme: scheme),
    ));
    await tester.pumpAndSettle();
    return scheme;
  }

  testWidgets('every tab can be opened without throwing', (tester) async {
    final scheme = await pumpShell(tester);

    for (final tab in ['DINING', 'EVENTS', 'MAP', 'CAMPUS', 'TODAY']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'opening $tab threw');
    }
    scheme.dispose();
  });

  testWidgets('leaving Customize for another tab does not throw',
      (tester) async {
    // The reported case. Customize puts the Today grid into its reorderable
    // editing mode, and the tab is then switched while that mode is live.
    final scheme = await pumpShell(tester);

    // The edit bar is a sliver below the grid, so it is not built until it is
    // scrolled into view.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    final customize = find.byIcon(Icons.tune_rounded);
    expect(customize, findsOneWidget, reason: 'no Customize control found');

    await tester.tap(customize, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'entering Customize threw');

    await tester.tap(find.text('CAMPUS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'leaving Customize for Campus threw');

    await tester.tap(find.text('TODAY'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'returning to Today threw');

    scheme.dispose();
  });

  testWidgets('repeated switching stays clean', (tester) async {
    // The leak grew with every visit, so the failure needed repetition to
    // show. Once is not a test of it.
    final scheme = await pumpShell(tester);

    for (var round = 0; round < 4; round++) {
      for (final tab in ['CAMPUS', 'MAP', 'EVENTS', 'DINING', 'TODAY']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'round $round threw on $tab');
      }
    }
    scheme.dispose();
  });

  testWidgets('the map has its own destination', (tester) async {
    // It was a section inside Campus, which buried it: the map is something
    // you open deliberately, not something you scroll past on the way to post
    // office hours.
    final scheme = await pumpShell(tester);

    expect(find.text('MAP'), findsOneWidget);
    await tester.tap(find.text('MAP'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    scheme.dispose();
  });

  testWidgets('a tab switch is covered while the new tab comes up',
      (tester) async {
    // Cole: switching pages "looks weird". The incoming tab assembles in view,
    // and the Map tab genuinely does work on first open. The veil covers that,
    // then gets out of the way on its own.
    final scheme = await pumpShell(tester);

    expect(find.byType(PageVeil), findsNothing,
        reason: 'nothing to cover before a switch happens');

    await tester.tap(find.text('MAP'));
    await tester.pump();
    expect(find.byType(PageVeil), findsOneWidget);
    expect(find.text('MAP'), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byType(PageVeil), findsNothing,
        reason: 'the veil must never outstay the tab it was covering');
    expect(tester.takeException(), isNull);

    scheme.dispose();
  });

  test('the shell holds its subscriptions', () {
    // Guards the specific regression: the shell re-subscribes on every refresh
    // tick, so it must cancel first or the count grows for as long as the app
    // is open.
    final source = File('lib/app_shell.dart').readAsStringSync();
    expect(source, contains('_subscriptions.cancelAll()'),
        reason: 'a refresh that does not cancel first stacks subscriptions');
    expect(source, contains('_subscriptions.dispose()'));
  });
}
