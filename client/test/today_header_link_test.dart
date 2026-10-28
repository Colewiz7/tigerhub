/// On a phone a Today card's header opens its tab, in place of "+N" footers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(RitClock.reset);

  final dining = [for (var i = 0; i < 9; i++) DiningLocation(id: i + 1, name: 'Hall $i', isOpen: true)];
  final events = [
    for (var i = 0; i < 6; i++)
      CampusEvent(uid: 'e$i', source: 'test', title: 'Meeting $i', startsAt: DateTime.utc(2026, 10, 14, 20 + i ~/ 3), endsAt: DateTime.utc(2026, 10, 14, 23), organizer: 'Club $i', organizerKey: 'club$i'),
  ];

  Future<List<int>> pumpToday(WidgetTester tester, {double width = 390}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 5000);
    addTearDown(tester.view.reset);
    final taps = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok(dining),
          events: _ok(events),
          chefs: _ok<MenuItem>(const []),
          areas: _ok<HousingArea>(const []),
          onRefresh: () async {},
          onGoToTab: taps.add,
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    return taps;
  }

  testWidgets('the Eat now header opens the Dining tab and Events opens Events', (tester) async {
    final taps = await pumpToday(tester);
    await tester.tap(find.text('Eat now'));
    await tester.pump();
    await tester.tap(find.text('Events'));
    await tester.pump();
    expect(taps, [1, 2]);
  });

  testWidgets('no +N open or +N organizers footer on a phone', (tester) async {
    await pumpToday(tester);
    expect(find.textContaining(RegExp(r'^\+\d+ ')), findsNothing);
  });

  testWidgets('from 600 wide the footer stays', (tester) async {
    await pumpToday(tester, width: 700);
    expect(find.textContaining(RegExp(r'^\+\d+ ')), findsWidgets);
  });

  testWidgets('the header is announced as a button that says where it goes', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpToday(tester);
    final link = find.bySemanticsLabel('Eat now, opens Dining');
    expect(link, findsOneWidget);
    expect(tester.getSemantics(link), isSemantics(isButton: true, hasTapAction: true));
    handle.dispose();
  });

  testWidgets('in edit mode the header does nothing', (tester) async {
    final taps = await pumpToday(tester);
    await tester.scrollUntilVisible(find.text('Customize'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Eat now'), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Eat now'), warnIfMissed: false);
    await tester.pump();
    expect(taps, isEmpty);
  });
}
