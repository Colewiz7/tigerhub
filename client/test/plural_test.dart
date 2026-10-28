/// One event, two events: every count with a noun agrees with its number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dashboard_event_cards.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/more_row.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
  home: Scaffold(body: SizedBox(width: 390, child: child)),
);

CampusEvent _event(int i) => CampusEvent(uid: 'e$i', source: 'test', title: 'Meeting $i', startsAt: DateTime.utc(2026, 10, 15, 20 + i), organizer: 'Robotics Club', organizerKey: 'robotics');

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(RitClock.reset);

  test('one drops the s, everything else keeps it', () {
    expect(counted(1, 'events'), '1 event');
    expect(counted(0, 'events'), '0 events');
    expect(counted(2, 'organizers'), '2 organizers');
    expect(counted(1, 'places'), '1 place');
    expect(counted(1, 'trucks'), '1 truck');
    expect(counted(1, 'open'), '1 open');
  });

  for (final (n, label) in const [(1, '1 event'), (2, '2 events')]) {
    testWidgets('the club card says $label', (tester) async {
      await tester.pumpWidget(_wrap(ScopedEventsCard(
        result: Result(value: Collection(data: [for (var i = 0; i < n; i++) _event(i)], stale: false), state: DataState.ok),
        organizerKey: 'robotics',
      )));
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('the more row says +1 organizer and +2 organizers', (tester) async {
    await tester.pumpWidget(_wrap(const MoreRow(hidden: 1, noun: 'organizers')));
    expect(find.text('+1 organizer'), findsOneWidget);
    await tester.pumpWidget(_wrap(const MoreRow(hidden: 2, noun: 'organizers')));
    expect(find.text('+2 organizers'), findsOneWidget);
  });
}
