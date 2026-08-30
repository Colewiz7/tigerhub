/// Parity between the Python backend and the Dart port.
///
/// Going client side meant translating roughly 1400 lines of scraping and 200
/// lines of date math out of Python. "It looks right" is not a good enough
/// check on hours logic, which is the one piece of real logic in dining and the
/// thing every screen depends on.
///
/// So both sides are run against the same captured upstream payload at the same
/// frozen instant, and the output is compared field by field. The golden files
/// were produced by `backend/app/hours.py` itself, so they keep testing the
/// port after the backend is deleted.
///
/// The four instants are chosen to exercise the paths that are easy to get
/// wrong, not just a convenient afternoon:
///
///   2026-08-30 14:30 EDT   ordinary Sunday afternoon
///   2026-08-31 00:30 EDT   inside an overnight span, the closes_next_day case
///   2026-09-02 07:45 EDT   morning, just before several openings
///   2026-11-02 22:10 EST   the day after DST ends, so the offset has changed
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/sources/tigercenter.dart';
import 'package:tigerhub/data/static_config.dart';

void main() {
  late Map<String, dynamic> snapshot;

  setUpAll(() {
    final raw = jsonDecode(
      File('test/fixtures/dining_all.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    snapshot = {
      'service_date': '2026-08-30',
      'locations': parseDining(raw),
    };

    StaticConfig.overrideForTesting({
      'dining_categories': jsonDecode(
        File('assets/config/dining_categories.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    });
  });

  /// Rebuild the /dining data array exactly as LocalBackend does.
  List<Map<String, dynamic>> build(DateTime now) {
    final config = StaticConfig.instance;
    final out = [
      for (final loc in snapshot['locations'] as List<dynamic>)
        buildDiningLocation(
          loc as Map<String, dynamic>,
          now,
          config,
          null,
        ),
    ];
    out.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return out;
  }

  const cases = {
    '2026-08-30T14-30-00-04-00.json': '2026-08-30T14:30:00-04:00',
    '2026-08-31T00-30-00-04-00.json': '2026-08-31T00:30:00-04:00',
    '2026-09-02T07-45-00-04-00.json': '2026-09-02T07:45:00-04:00',
    '2026-11-02T22-10-00-05-00.json': '2026-11-02T22:10:00-05:00',
  };

  cases.forEach((file, instant) {
    test('dining matches the backend at $instant', () {
      final expected = (jsonDecode(
        File('test/golden/dining_parity/$file').readAsStringSync(),
      ) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final actual = build(DateTime.parse(instant));

      expect(actual.length, expected.length,
          reason: 'location count drifted from the backend');

      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = actual[i];
        for (final key in want.keys) {
          // Deep equality, not encoded strings: the backend serialised nested
          // objects with sorted keys and this port preserves insertion order,
          // which is not a behaviour difference.
          expect(
            got[key],
            equals(want[key]),
            reason: '${want['name']} (id ${want['id']}) field "$key" '
                'differs from the backend at $instant',
          );
        }
      }
    });
  });

  group('campus time', () {
    test('knows when Eastern is on daylight time', () {
      // 2026: DST runs 8 March to 1 November.
      expect(CampusTime.isDaylight(DateTime.utc(2026, 3, 8, 6, 59)), isFalse);
      expect(CampusTime.isDaylight(DateTime.utc(2026, 3, 8, 7, 1)), isTrue);
      expect(CampusTime.isDaylight(DateTime.utc(2026, 11, 1, 5, 59)), isTrue);
      expect(CampusTime.isDaylight(DateTime.utc(2026, 11, 1, 6, 1)), isFalse);
    });

    test('formats with the offset that actually applied', () {
      expect(
        CampusTime.format(DateTime.utc(2026, 8, 31, 11, 30)),
        '2026-08-31T07:30:00-04:00',
      );
      expect(
        CampusTime.format(DateTime.utc(2026, 12, 31, 12, 30)),
        '2026-12-31T07:30:00-05:00',
      );
    });

    test('does not follow the device clock', () {
      // The whole point: a laptop in another timezone still reads RIT's hours.
      // wall() names a campus reading, so it must land on the same instant no
      // matter where DateTime.now() happens to be.
      final noon = CampusTime.wall(2026, 8, 31, 12);
      expect(CampusTime.format(noon), '2026-08-31T12:00:00-04:00');
      expect(noon.isUtc, isTrue);
    });
  });
}
