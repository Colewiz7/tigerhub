/// Parity for the targeted occupancy extractor.
///
/// This deliberately does not use the general turbo-stream decoder, matching
/// docs/notes.md section 8 decision 1: only four fields plus a 24 hour series are
/// needed out of one known object. Both extractors exist in the app now, so it
/// is worth being explicit that this one is the narrow one, on purpose.
///
/// Checked against the backend over a real 226 KB payload from Crossroads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/maps_occupancy.dart';

void main() {
  String payload() =>
      File('test/fixtures/maps_occupancy_123.data').readAsStringSync();

  test('occupancy extracts identically to the backend', () {
    final actual = parseOccupancy(payload(), 123)!;
    final expected = jsonDecode(
      File('test/golden/occupancy_parse.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    for (final key in expected.keys) {
      expect(actual[key], equals(expected[key]), reason: 'field "$key" differs');
    }
    expect((actual['hourly'] as List).length, 24,
        reason: 'the 24 hour series is what makes the chart possible');
  });

  group('occupancy failure is contained', () {
    // A format change must hide the chip, never break the dining response.
    test('returns null rather than throwing on junk', () {
      expect(parseOccupancy('', 123), isNull);
      expect(parseOccupancy('not json', 123), isNull);
      expect(parseOccupancy('{"a":1}', 123), isNull);
      expect(parseOccupancy('[1,2,3]', 123), isNull);
    });

    test('returns null when the page simply has no sensor', () {
      // 19 of the 24 dining locations publish no densityData at all. That is
      // the normal case, not an error.
      expect(parseOccupancy('["somethingElse",{"_0":1}]', 123), isNull);
    });
  });
}
