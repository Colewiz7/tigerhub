/// Eat now: your open spots, then other open places, then your closed spots
/// only when rows are left. Closed places you did not pin stay off the card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/status_row.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(() {
    RitClock.reset();
    Preferences.instance.resetForTests();
  });

  DiningLocation place(int id, String name, {bool open = true}) => DiningLocation(id: id, name: name, isOpen: open);

  group('the order', () {
    test('open pins, open others, closed pins, nothing else', () {
      final order = eatNowOrder([
        place(1, 'Closed plain', open: false),
        place(2, 'Open plain'),
        place(3, 'Closed pin', open: false),
        place(4, 'Open pin'),
      ], {'3', '4'});
      expect([for (final l in order) l.name], ['Open pin', 'Open plain', 'Closed pin']);
    });

    test('a closed pin never outranks an open place', () {
      final order = eatNowOrder([place(1, 'Closed pin', open: false), place(2, 'A'), place(3, 'B'), place(4, 'C')], {'1'});
      expect(order.take(3).map((l) => l.name), ['A', 'B', 'C']);
    });
  });

  Future<void> pump(WidgetTester tester, List<DiningLocation> places, {double width = 390}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 2000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: SingleChildScrollView(
          child: width >= 600
              ? SizedBox(height: 560, child: DiningCard(result: Result(value: Collection(data: places, stale: false), state: DataState.ok), onShowAll: () {}))
              : DiningCard(result: Result(value: Collection(data: places, stale: false), state: DataState.ok), onShowAll: () {}),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('on a phone the card is Eat now with N open', (tester) async {
    await pump(tester, [place(1, 'A'), place(2, 'B'), place(3, 'C', open: false)]);
    expect(find.text('Eat now'), findsOneWidget);
    expect(find.text('2 open'), findsOneWidget);
    expect(find.text('C'), findsNothing, reason: 'a closed place you did not pin');
  });

  testWidgets('from 600 wide it stays Dining', (tester) async {
    await pump(tester, [place(1, 'A'), place(2, 'B')], width: 700);
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Eat now'), findsNothing);
  });

  testWidgets('late at night a closed pin fills a spare row, quiet', (tester) async {
    await Preferences.instance.togglePinned(3);
    await pump(tester, [place(1, 'Open late'), place(2, 'Closed plain', open: false), place(3, 'Closed pin', open: false)]);
    expect(find.text('Open late'), findsOneWidget);
    expect(find.text('Closed pin'), findsOneWidget);
    expect(find.text('Closed plain'), findsNothing);
    final rows = tester.widgetList<StatusRow>(find.byType(StatusRow)).toList();
    expect(rows.last.emphasis, RowEmphasis.quiet);
    expect(tester.getTopLeft(find.text('Open late')).dy, lessThan(tester.getTopLeft(find.text('Closed pin')).dy));
  });

  testWidgets('three open places leave no row for a closed pin', (tester) async {
    await Preferences.instance.togglePinned(9);
    await pump(tester, [place(1, 'A'), place(2, 'B'), place(3, 'C'), place(9, 'Closed pin', open: false)]);
    expect(find.text('Closed pin'), findsNothing);
  });

  testWidgets('with nothing open and no pins it says all closed', (tester) async {
    await pump(tester, [place(1, 'A', open: false)]);
    expect(find.text('All closed'), findsOneWidget);
    expect(find.byType(StatusRow), findsNothing);
  });
}
