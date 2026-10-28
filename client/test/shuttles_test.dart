/// Shuttle service windows from the bundled schedule.
///
/// RIT publishes hours per route, not departures, so the only honest answers
/// are how many routes are left today and until when.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/shuttles.dart';

void main() {
  final json = jsonDecode(File('assets/config/shuttles.json').readAsStringSync()) as Map<String, dynamic>;
  final schedule = ShuttleSchedule.parse(json);

  test('the table names its source and when it was checked', () {
    expect(json['source_url'], 'https://www.rit.edu/parking/campus-shuttles');
    expect(json['last_verified'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('every area the app had keeps its routes', () {
    for (final area in ['global-village', 'residence-halls', 'perkins-green', 'riverknoll', 'university-commons']) {
      expect(schedule.covers(area), isTrue, reason: area);
    }
    expect(schedule.covers('greek-houses'), isFalse);
    expect(schedule.covers(null), isFalse);
  });

  // 2026-10-28 is a wednesday, 2026-10-31 a saturday, 2026-11-02 a monday
  List<int> numbers(String area, DateTime day) => [for (final r in schedule.routesOn(area, day)) r.number];

  test('weekdays and weekends run different routes, break routes never', () {
    expect(numbers('global-village', DateTime(2026, 10, 28)), [3, 4, 5]);
    expect(numbers('global-village', DateTime(2026, 10, 31)), [12, 13]);
    expect(numbers('perkins-green', DateTime(2026, 10, 28)), [7, 9, 11]);
  });

  test('hours read the way the schedule page writes them', () {
    final route = schedule.routesOn('global-village', DateTime(2026, 10, 31)).last;
    expect(route.hours, '7:47 AM–12:33 AM');
    expect(schedule.routesOn('global-village', DateTime(2026, 10, 28)).first.hours, '7:00 AM–11:16 PM');
  });

  test('Labor Day 2026 runs the holiday service', () {
    final routes = schedule.routesOn('global-village', DateTime(2026, 9, 7));
    expect([for (final r in routes) r.number], [1, 14]);
    expect(routes.first.hours, 'See the holiday timetable');
    expect(routes.last.hours, '7:20 AM–12:06 AM');
  });

  group('the window', () {
    test('a weekday afternoon from Global Village is 3 routes until 11:16 PM', () {
      final window = schedule.windowAt('global-village', DateTime(2026, 10, 28, 15));
      expect(window.state, ShuttleState.running);
      expect(window.routes, 3);
      expect(window.minute, 23 * 60 + 16);
    });

    test('before service starts it says when it starts', () {
      final window = schedule.windowAt('global-village', DateTime(2026, 10, 28, 4, 30));
      expect(window.state, ShuttleState.before);
      expect(window.minute, 5 * 60);
    });

    test('after the last route ends it is done for the day', () {
      final window = schedule.windowAt('global-village', DateTime(2026, 10, 28, 23, 20));
      expect(window.state, ShuttleState.done);
    });

    test('a sunday route past midnight still counts early monday', () {
      final window = schedule.windowAt('global-village', DateTime(2026, 11, 2, 0, 20));
      expect(window.state, ShuttleState.running);
      expect(window.routes, 1);
      expect(window.minute, 33);
    });

    test('and is gone once it ends', () {
      final window = schedule.windowAt('global-village', DateTime(2026, 11, 2, 0, 40));
      expect(window.state, ShuttleState.before);
    });

    test('an area with no table has no window', () {
      expect(schedule.windowAt('greek-houses', DateTime(2026, 10, 28, 15)).state, ShuttleState.none);
    });
  });
}
