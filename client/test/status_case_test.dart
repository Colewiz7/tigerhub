/// Status words are sentence case on screen: Open, Closed, Busy, Ended, All day.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/week_grid.dart';

// same list as scripts/copy_style.py
final _shouted = RegExp(r'(?<![A-Za-z])(OPEN|OPENS|CLOSED|CLOSES|CLOSING|BUSY|QUIET|ENDED|ALL DAY|LIVE|SOON|FULL)(?![A-Za-z])');

DiningLocation _place(String name, {bool open = true, bool hours = true, bool over = false}) => DiningLocation(
  id: name.hashCode,
  name: name,
  isOpen: open,
  category: 'other',
  categoryName: 'Everything else',
  categoryOrder: 3,
  closesAt: open && hours ? DateTime(2026, 8, 28, 22) : null,
  opensAt: !open && hours ? DateTime(2026, 8, 29, 7) : null,
  occupancy: over ? const Occupancy(count: 30, maxOcc: 20, percentFull: 100, overCapacity: true) : null,
);

CampusEvent _event(DateTime start, {DateTime? end, bool allDay = false}) => CampusEvent(
  uid: 'u$start',
  source: 'campusgroups',
  title: 'Dodgeball',
  startsAt: start,
  endsAt: end,
  allDay: allDay,
);

List<String> _shownText(WidgetTester tester) => [
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) widget.text.toPlainText(),
];

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('no status word is shown in all caps', (tester) async {
    final now = DateTime(2026, 8, 28, 14);
    final gym = RecreationDay.fromJson({'service_date': '2026-08-30', 'closed': true, 'note': 'CLOSED', 'spans': []});
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: ListView(children: [
          // wide, so the hero is the scalloped badge with its caption
          DiningCard(result: Result(value: Collection(data: [_place('Gracie')], stale: false), state: DataState.ok)),
          DiningRow(location: _place('Beanz')),
          DiningRow(location: _place('Brick City', hours: false)),
          DiningRow(location: _place('Ctrl Alt Deli', open: false)),
          DiningRow(location: _place('Cantina', open: false, hours: false)),
          DiningRow(location: _place('Midnight Oil', over: true)),
          EventRow(event: _event(DateTime(2026, 8, 28, 9), end: DateTime(2026, 8, 28, 10)), now: now),
          EventRow(event: _event(DateTime(2026, 8, 28), allDay: true), now: now),
          WeekGrid(rows: [WeekRow(label: 'Sunday', spans: const [], note: gym.note)]),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final shown = _shownText(tester);
    expect(shown, containsAll(['Open · until 10:00 PM', 'Closed · hours unavailable', 'Busy', 'Ended', 'All day', 'Closed']));
    final shouted = [for (final line in shown) if (_shouted.hasMatch(line)) line];
    expect(shouted, isEmpty);
  });
}
