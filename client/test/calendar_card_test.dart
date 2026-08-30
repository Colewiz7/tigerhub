/// The week calendar.
///
/// It answers a different question from the Events feed: not "what is on" but
/// "which day". The bucketing is what carries that, so it is tested directly:
/// an empty Thursday has to survive as an empty Thursday rather than being
/// dropped, or the strip collapses back into a list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/calendar_card.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

CampusEvent event(String title, DateTime startsAt, {String? organizerKey}) =>
    CampusEvent(
      uid: '$title-${startsAt.toIso8601String()}',
      source: 'campusgroups',
      title: title,
      startsAt: startsAt,
      organizer: organizerKey == null ? null : 'Club $organizerKey',
      organizerKey: organizerKey,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A Wednesday.
  final now = CampusTime.wall(2026, 9, 2, 10, 0);

  group('bucketing', () {
    test('covers seven days starting today', () {
      final week = calendarWeek(const [], now: now);
      expect(week.length, calendarDays);
      expect(week.first.isToday, isTrue);
      expect(week.skip(1).every((d) => !d.isToday), isTrue);
    });

    test('keeps a day with nothing on it', () {
      // An empty day is information. Dropping it would turn the strip back
      // into the list it exists to not be.
      final week = calendarWeek(
        [event('Only Friday', CampusTime.wall(2026, 9, 4, 18, 0))],
        now: now,
      );
      expect(week.length, calendarDays);
      expect(week.where((d) => d.events.isEmpty).length, calendarDays - 1);
    });

    test('puts an event on its own campus day', () {
      final week = calendarWeek(
        [event('Friday thing', CampusTime.wall(2026, 9, 4, 18, 0))],
        now: now,
      );
      // Wednesday is index 0, so Friday is index 2.
      expect(week[2].events.single.title, 'Friday thing');
    });

    test('a late evening event does not slide into the next day', () {
      // 11pm campus time is 03:00 UTC the following day. Bucketing on the raw
      // UTC date would move it, and the calendar would be wrong every night.
      final week = calendarWeek(
        [event('Late', CampusTime.wall(2026, 9, 2, 23, 30))],
        now: now,
      );
      expect(week.first.events.single.title, 'Late');
      expect(week[1].events, isEmpty);
    });

    test('orders a day by start time', () {
      final week = calendarWeek(
        [
          event('Evening', CampusTime.wall(2026, 9, 2, 19, 0)),
          event('Morning', CampusTime.wall(2026, 9, 2, 8, 0)),
        ],
        now: now,
      );
      expect(week.first.events.map((e) => e.title), ['Morning', 'Evening']);
    });

    test('a day names the campus date, not the day before it', () {
      // CalendarDay.date is UTC midnight whose fields are already campus
      // local. Running it back through CampusTime.fieldsOf applies the offset
      // twice and lands on the previous evening, which shifted every cell in
      // the strip back a day.
      final week = calendarWeek(const [], now: now);
      expect(week.first.date.day, 2);
      expect(week.first.date.weekday, DateTime.wednesday);
      expect(week.last.date.day, 8);
    });

    test('drops anything outside the week', () {
      final week = calendarWeek(
        [
          event('Yesterday', CampusTime.wall(2026, 9, 1, 12, 0)),
          event('Next month', CampusTime.wall(2026, 10, 5, 12, 0)),
        ],
        now: now,
      );
      expect(week.every((d) => d.events.isEmpty), isTrue);
    });
  });

  group('rendering', () {
    Future<void> pump(
      WidgetTester tester,
      List<CampusEvent> events, {
      String? organizerKey,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(700, 900);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: CalendarCard(
            now: now,
            organizerKey: organizerKey,
            result: Result(
              value: Collection(data: events, stale: false),
              state: DataState.ok,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a cell for every day of the week', (tester) async {
      await pump(tester, [event('A', CampusTime.wall(2026, 9, 2, 12, 0))]);
      // Seven day numbers: 2 through 8.
      for (final day in [2, 3, 4, 5, 6, 7, 8]) {
        expect(find.text('$day'), findsWidgets, reason: 'day $day missing');
      }
    });

    testWidgets('an empty day says so rather than looking broken',
        (tester) async {
      await pump(tester, [event('Friday', CampusTime.wall(2026, 9, 4, 18, 0))]);
      // Today is empty and selected by default.
      expect(find.text('Nothing on today'), findsOneWidget);
    });

    testWidgets('selecting a day lists that day', (tester) async {
      await pump(tester, [event('Friday', CampusTime.wall(2026, 9, 4, 18, 0))]);

      expect(find.text('Friday'), findsNothing);
      await tester.tap(find.text('4').first);
      await tester.pumpAndSettle();
      expect(find.text('Friday'), findsOneWidget);
    });

    testWidgets('a scoped calendar shows only that club', (tester) async {
      await pump(
        tester,
        [
          event('Ours', CampusTime.wall(2026, 9, 2, 12, 0), organizerKey: 'A'),
          event('Theirs', CampusTime.wall(2026, 9, 2, 13, 0), organizerKey: 'B'),
        ],
        organizerKey: 'A',
      );

      expect(find.text('Ours'), findsOneWidget);
      expect(find.text('Theirs'), findsNothing);
      expect(find.text('Club A'), findsOneWidget,
          reason: 'a scoped calendar should be titled by its club');
    });
  });
}
