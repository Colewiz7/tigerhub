/// Parity for the gym and pool hours scrape.
///
/// This is the only HTML scrape in the app, and the only source whose markup
/// RIT can change without warning, so it is pinned against the backend over a
/// captured copy of the real page: 9 facilities, 75 rows.
///
/// The date is frozen, because the page publishes "the next seven days starting
/// today" and resolves weekday labels against the current date.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/recreation.dart';

void main() {
  test('recreation hours parse identically to the backend', () {
    final actual = parseRecreation(
      File('test/fixtures/recreation.html').readAsStringSync(),
      today: DateTime.utc(2026, 8, 30),
    );

    final expected = (jsonDecode(
      File('test/golden/recreation_parse.json').readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(actual.length, expected.length, reason: 'row count differs');

    for (var i = 0; i < expected.length; i++) {
      for (final key in expected[i].keys) {
        expect(
          actual[i][key],
          equals(expected[i][key]),
          reason: 'row $i (${expected[i]['facility']}) field "$key" differs',
        );
      }
    }
  });

  group('recreation time parsing', () {
    test('reads the prose forms the page actually uses', () {
      expect(parseRecreationTime('6:45am'), '06:45');
      expect(parseRecreationTime('10am'), '10:00');
      expect(parseRecreationTime('12pm'), '12:00');
      expect(parseRecreationTime('12am'), '00:00');
      expect(parseRecreationTime('noon'), '12:00');
      expect(parseRecreationTime('midnight'), '00:00');
      expect(parseRecreationTime('7 p.m.'), '19:00');
      expect(parseRecreationTime('whenever'), isNull);
    });

    test('splits a multi session pool day into separate spans', () {
      // A single open-to-close range here would claim the pool is open all
      // afternoon when it is shut between sessions.
      expect(
        parseHoursCell('6:45am - 8:45am, 12pm - 1:45pm, 7pm - 10pm'),
        [
          {'opens_at': '06:45', 'closes_at': '08:45'},
          {'opens_at': '12:00', 'closes_at': '13:45'},
          {'opens_at': '19:00', 'closes_at': '22:00'},
        ],
      );
    });

    test('treats a closed cell as no spans', () {
      expect(parseHoursCell('Closed'), isEmpty);
      expect(parseHoursCell('<td>CLOSED</td>'), isEmpty);
    });

    test('finds the weekday even when the header runs into the row', () {
      // The markup yields 'Date Hours Saturday (Today)'. Taking the first word
      // gave 'Date' and dropped today entirely.
      expect(weekdayOf('Date Hours Saturday (Today)'), 5);
      expect(weekdayOf('Monday'), 0);
      expect(weekdayOf('no day here'), isNull);
    });
  });
}
