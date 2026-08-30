/// Merging the same event arriving from more than one feed.
///
/// CLAUDE.md section 8 decision 2 shipped no dedupe on purpose so the overlap
/// could be measured first. It was: 138 collisions across 1604 events, exact on
/// a normalised title plus the start instant. These tests pin the behaviour
/// that follows, including the part that is easy to get wrong, which is that
/// the copies are not interchangeable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/merge_events.dart';
import 'package:tigerhub/data/sources/athletics.dart';
import 'package:tigerhub/data/sources/campusgroups.dart';
import 'package:tigerhub/data/sources/drupal_events.dart';

Map<String, dynamic> event({
  required String uid,
  required String source,
  required String title,
  required String startsAt,
  String? organizer,
  String? organizerKey,
  String? location,
  String? building,
  String? url,
}) =>
    {
      'uid': uid,
      'source': source,
      'title': title,
      'starts_at': startsAt,
      'organizer': organizer,
      'organizer_key': organizerKey,
      'location': location,
      'building': building,
      'url': url,
      'ends_at': null,
      'description': null,
      'room': null,
      'event_type': null,
      'all_day': false,
    };

void main() {
  group('identity', () {
    test('ignores case and punctuation but not the words', () {
      expect(normaliseTitle('Co-op Connections!'), 'co op connections');
      expect(normaliseTitle('CO OP   connections'), 'co op connections');
      expect(normaliseTitle('Co-op Connection'), isNot('co op connections'));
    });

    test('the same instant written two ways is one event', () {
      final a = event(
        uid: 'a', source: drupalSource, title: 'Talk',
        startsAt: '2026-09-01T16:00:00-04:00',
      );
      final b = event(
        uid: 'b', source: campusGroupsSource, title: 'Talk',
        startsAt: '2026-09-01T20:00:00Z',
      );
      expect(eventKey(a), eventKey(b),
          reason: 'the feeds store different offsets for the same moment');
    });

    test('a different time is a different event', () {
      final a = event(
        uid: 'a', source: drupalSource, title: 'Talk',
        startsAt: '2026-09-01T16:00:00-04:00',
      );
      final b = event(
        uid: 'b', source: drupalSource, title: 'Talk',
        startsAt: '2026-09-08T16:00:00-04:00',
      );
      expect(eventKey(a), isNot(eventKey(b)),
          reason: 'a weekly series must not collapse to one entry');
    });
  });

  group('merging', () {
    test('keeps the club organizer over Drupal saying "RIT"', () {
      final merged = mergeDuplicateEvents([
        event(
          uid: 'd', source: drupalSource, title: 'Co-op Connections',
          startsAt: '2026-09-16T19:00:00Z',
          organizer: 'RIT', organizerKey: 'RIT',
          building: 'Bausch & Lomb Center',
        ),
        event(
          uid: 'c', source: campusGroupsSource, title: 'Co-op Connections',
          startsAt: '2026-09-16T19:00:00Z',
          organizer: 'Office of Career Services', organizerKey: 'CAREERS',
          location: 'BLC Atrium',
        ),
      ]);

      expect(merged.length, 1);
      // Dropping the CampusGroups copy would silently break muting for this
      // event: the survivor would claim to be organised by "RIT".
      expect(merged.single['organizer_key'], 'CAREERS');
      expect(merged.single['organizer'], 'Office of Career Services');
      // And the field only Drupal had is still there.
      expect(merged.single['building'], 'Bausch & Lomb Center');
      expect(merged.single['location'], 'BLC Atrium');
    });

    test('athletics wins over both, since it names the sport', () {
      final merged = mergeDuplicateEvents([
        event(
          uid: 'd', source: drupalSource, title: "Women's Soccer vs Geneseo",
          startsAt: '2026-09-01T20:00:00Z',
          organizer: 'RIT', organizerKey: 'RIT',
        ),
        event(
          uid: 'a', source: athleticsSource, title: "Women's Soccer vs Geneseo",
          startsAt: '2026-09-01T20:00:00Z',
          organizer: "Women's Soccer", organizerKey: "WOMEN'S_SOCCER",
          location: 'Rochester, N.Y. / Judson Stadium',
        ),
      ]);

      expect(merged.single['organizer'], "Women's Soccer");
      expect(merged.single['location'], 'Rochester, N.Y. / Judson Stadium');
    });

    test('records which feeds carried it', () {
      final merged = mergeDuplicateEvents([
        event(uid: 'd', source: drupalSource, title: 'X', startsAt: '2026-09-01T20:00:00Z'),
        event(uid: 'c', source: campusGroupsSource, title: 'X', startsAt: '2026-09-01T20:00:00Z'),
      ]);
      expect(merged.single['merged_from'], [campusGroupsSource, drupalSource]);
    });

    test('is deterministic whatever order the feeds are read in', () {
      final a = event(uid: 'd', source: drupalSource, title: 'X', startsAt: '2026-09-01T20:00:00Z', organizer: 'RIT');
      final b = event(uid: 'c', source: campusGroupsSource, title: 'X', startsAt: '2026-09-01T20:00:00Z', organizer: 'Club');

      expect(
        jsonEncode(mergeDuplicateEvents([a, b])),
        jsonEncode(mergeDuplicateEvents([b, a])),
      );
    });

    test('leaves a unique event exactly as it was', () {
      final only = event(uid: 'x', source: drupalSource, title: 'Solo', startsAt: '2026-09-01T20:00:00Z');
      final merged = mergeDuplicateEvents([only]);
      expect(merged.single, same(only),
          reason: 'the common case must not be rebuilt for nothing');
    });

    test('passes through a record it cannot key, rather than dropping it', () {
      final broken = event(uid: 'x', source: drupalSource, title: '', startsAt: 'not a date');
      expect(mergeDuplicateEvents([broken]).length, 1);
    });
  });

  test('collapses the real overlap in the captured feeds', () {
    final events = <Map<String, dynamic>>[];
    events.addAll(parseCampusGroups(
      File('test/fixtures/campusgroups.ics').readAsStringSync()));
    events.addAll(parseAthletics(
      File('test/fixtures/athletics.ics').readAsStringSync()));
    events.addAll(parseDrupal(
      jsonDecode(File('test/fixtures/drupal_events.json').readAsStringSync())
          as List<dynamic>));

    final merged = mergeDuplicateEvents(events);
    final removed = events.length - merged.length;

    expect(events.length, 1604, reason: 'the captured feeds changed size');
    expect(removed, greaterThan(100),
        reason: 'the measured overlap was 138 duplicate records');

    // Nothing may be invented, and nothing may vanish beyond the duplicates.
    expect(merged.length, events.length - removed);

    final multi = merged.where((e) => e['merged_from'] != null).length;
    expect(multi, greaterThan(0));
    expect(multi, lessThanOrEqualTo(removed + multi));
  });
}
