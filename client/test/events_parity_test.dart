/// Parity for the iCal sources.
///
/// The backend used Python's `icalendar`; this port hand rolls the parsing,
/// which is only defensible if it produces exactly the same records. So both
/// run over the same captured feeds and every field of every event is compared:
/// 962 CampusGroups events and 182 athletics fixtures, 1144 records in total.
///
/// The two feeds are deliberately both covered, because they exercise different
/// paths. CampusGroups is uniform UTC timestamps with X-CG-CATEGORY parameters
/// and postal addresses that need trimming. Athletics mixes UTC timestamps with
/// `VALUE=DATE` all day entries, escapes commas inside LOCATION, and keeps the
/// location whole rather than trimming it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/ical.dart';
import 'package:tigerhub/data/sources/athletics.dart';
import 'package:tigerhub/data/sources/campusgroups.dart';
import 'package:tigerhub/data/sources/drupal_events.dart';

void main() {
  List<Map<String, dynamic>> golden(String name) =>
      (jsonDecode(File('test/golden/$name.json').readAsStringSync())
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  void compare(
    List<Map<String, dynamic>> actual,
    List<Map<String, dynamic>> expected,
    String label, {
    Set<String> except = const {},
  }) {
    actual.sort((a, b) {
      final byUid = (a['uid'] as String).compareTo(b['uid'] as String);
      return byUid != 0
          ? byUid
          : (a['starts_at'] as String).compareTo(b['starts_at'] as String);
    });

    expect(actual.length, expected.length,
        reason: '$label event count drifted from the backend');

    for (var i = 0; i < expected.length; i++) {
      for (final key in expected[i].keys) {
        if (except.contains(key)) continue;
        final want = expected[i][key];
        final got = actual[i][key];

        // The scraper stored UTC as "+00:00" and the API layer re-serialised it
        // as "Z". Same instant, different spelling, and this port emits the API
        // level form, so timestamps are compared as instants rather than text.
        if ((key == 'starts_at' || key == 'ends_at') &&
            want is String &&
            got is String) {
          expect(
            DateTime.parse(got).toUtc(),
            DateTime.parse(want).toUtc(),
            reason: '$label "${expected[i]['title']}" field "$key" differs',
          );
          continue;
        }

        expect(
          got,
          equals(want),
          reason: '$label "${expected[i]['title']}" field "$key" differs',
        );
      }
    }
  }

  test('campusgroups parses identically to the backend', () {
    compare(
      parseCampusGroups(
        File('test/fixtures/campusgroups.ics').readAsStringSync(),
      ),
      golden('campusgroups_parse'),
      'campusgroups',
    );
  });

  test('athletics parses identically to the backend', () {
    compare(
      parseAthletics(File('test/fixtures/athletics.ics').readAsStringSync()),
      golden('athletics_parse'),
      'athletics',
    );
  });

  List<Map<String, dynamic>> drupalActual() => parseDrupal(
        jsonDecode(File('test/fixtures/drupal_events.json').readAsStringSync())
            as List<dynamic>,
      );

  test('drupal parses identically to the backend, except for the time fix', () {
    // The three time fields are deliberately excluded: the backend got them
    // wrong and this port does not reproduce the bug. See the test below for
    // what it does instead. Everything else must still match exactly.
    compare(
      drupalActual(),
      golden('drupal_parse'),
      'drupal',
      except: {'starts_at', 'ends_at', 'all_day'},
    );
  });

  group('drupal times', () {
    test('reads the 12 hour clock Drupal actually publishes', () {
      expect(parseClockOf('3:00 PM'), (15, 0, 0));
      expect(parseClockOf('12:00 AM'), (0, 0, 0));
      expect(parseClockOf('12:00 PM'), (12, 0, 0));
      expect(parseClockOf('11:33 AM'), (11, 33, 0));
      // The 24 hour forms the backend did handle still work.
      expect(parseClockOf('15:00'), (15, 0, 0));
      expect(parseClockOf('15:00:30'), (15, 0, 30));
      expect(parseClockOf('nonsense'), isNull);
    });

    test('stops marking timed events as all day', () {
      // The bug: 456 of 460 official RIT events carried a stated start time
      // that was discarded, so the Events tab showed everything from RIT as
      // ALL DAY. Only 4 records genuinely have no time.
      final parsed = drupalActual();
      final timed = parsed.where((e) => e['all_day'] == false).length;

      expect(parsed.length, 460);
      expect(timed, 456, reason: 'these are the events the backend lost');
      expect(
        golden('drupal_parse').where((e) => e['all_day'] == false).length,
        0,
        reason: 'the backend marked every single one all day',
      );
    });

    test('places an afternoon event in the afternoon', () {
      final parsed = drupalActual();
      final afternoon = parsed.firstWhere(
        (e) => (e['starts_at'] as String).contains('T15:00:00'),
      );
      expect(afternoon['all_day'], isFalse);
      expect(afternoon['starts_at'], contains('T15:00:00'));
    });
  });

  group('ical parsing', () {
    test('unfolds continuation lines', () {
      expect(
        unfold('SUMMARY:one\r\n two\r\nUID:x'),
        ['SUMMARY:onetwo', 'UID:x'],
      );
    });

    test('unescapes text, so a location is not cut at a fake comma', () {
      // Athletics sends "Rochester\, N.Y. / Judson Stadium". Splitting before
      // unescaping would leave "Rochester\" as the venue.
      expect(
        unescapeText(r'Rochester\, N.Y. / Judson Stadium'),
        'Rochester, N.Y. / Judson Stadium',
      );
      expect(unescapeText(r'a\nb'), 'a\nb');
      expect(unescapeText(r'a\\b'), r'a\b');
    });

    test('does not split on a colon inside a quoted parameter', () {
      final p = parseLine('ORGANIZER;CN="A: B":mailto:x@y.z')!;
      expect(p.name, 'ORGANIZER');
      expect(p.params['CN'], 'A: B');
      expect(p.value, 'mailto:x@y.z');
    });

    test('reads both date forms', () {
      expect(
        parseMoment(parseLine('DTSTART:20260901T200000Z'))!.allDay,
        isFalse,
      );
      final allDay = parseMoment(parseLine('DTSTART;VALUE=DATE:20260901'))!;
      expect(allDay.allDay, isTrue);
      // Midnight campus time, which in September is UTC-4.
      expect(allDay.instant, DateTime.utc(2026, 9, 1, 4));
    });

    test('keeps repeated properties apart by their parameters', () {
      final event = parseEvents(
        'BEGIN:VEVENT\r\n'
        'CATEGORIES;X-CG-CATEGORY=club_acronym:FOODSHARE\r\n'
        'CATEGORIES;X-CG-CATEGORY=event_type:Meeting\r\n'
        'END:VEVENT',
      ).single;
      expect(categoriesOf(event), ('FOODSHARE', 'Meeting'));
    });
  });

  group('athletics organizer', () {
    test('pulls the sport off a fixture title', () {
      expect(sportOf("Women's Soccer vs Geneseo - Pride Game"), "Women's Soccer");
      expect(sportOf('Baseball at Ithaca'), 'Baseball');
    });

    test('falls back to leading words for meets', () {
      expect(sportOf('Track Invitational at home'), 'Track Invitational');
    });
  });
}
