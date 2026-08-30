import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/events_card.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';

CampusEvent _event(String uid, DateTime startsAt) => CampusEvent(
  uid: uid,
  source: 'test',
  title: 'Event $uid',
  startsAt: startsAt,
);

void main() {
  test('eventsToday compares calendar days in local time', () {
    final now = DateTime(2026, 8, 30, 12);
    final events = [
      _event('morning', DateTime(2026, 8, 30, 8)),
      _event('evening', DateTime(2026, 8, 30, 20)),
      _event('tomorrow', DateTime(2026, 8, 31, 9)),
    ];

    expect(eventsToday(events, now: now), 2);
  });

  testWidgets('events card gives today one focal badge', (tester) async {
    final now = DateTime.now();
    final events = [
      _event('today', now),
      _event('later', now.add(const Duration(days: 2))),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 520,
            child: EventsCard(
              result: Result(
                value: Collection(data: events, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ScallopedBadge), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('empty events card does not invent a hero value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 520,
            child: EventsCard(
              result: Result(
                value: Collection<CampusEvent>(data: [], stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ScallopedBadge), findsNothing);
  });
}
