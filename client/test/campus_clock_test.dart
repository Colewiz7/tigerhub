/// Anything that means "now on campus" has to come from CampusTime.
///
/// CampusTime exists because the device clock is not RIT's clock. A laptop set
/// to another timezone, or a student travelling, must still see the campus's
/// own hours and the campus's own hour.
///
/// Two places were reading the device clock instead:
///
///   - the occupancy chart's "now" marker. maps.rit.edu indexes
///     intra_loc_hours by RIT's wall clock, so on any other timezone the
///     marker sat on the wrong bar and busynessCaption compared the wrong
///     hour against its average.
///   - the post office season. Fall hours start on 22 August, so a device an
///     hour ahead would have flipped a day early.
///
/// These are source guards rather than behavioural tests because the values
/// are read inline at build time, and a test cannot move the machine's
/// timezone. They fail loudly if the device clock creeps back in.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/screens/campus_screen.dart';

void main() {
  test('the occupancy hour comes from the campus clock', () {
    final source = File(
      'lib/widgets/dining_detail_sheet.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('CampusTime.fieldsOf(CampusTime.nowUtc()).hour'),
      reason: 'the now marker must be RIT\'s hour, not the device\'s',
    );
    expect(
      source,
      isNot(contains('DateTime.now().hour')),
      reason: 'the device hour is not the campus hour',
    );
  });

  test('the post office season comes from the campus clock', () {
    final source = File('lib/screens/campus_screen.dart').readAsStringSync();
    expect(source, isNot(contains('currentSeason(DateTime.now())')));
    expect(source, contains('currentSeason(CampusTime.'));
  });

  group('the season boundary itself', () {
    test('fall starts on 22 August, not on the 1st', () {
      // RIT publishes the changeover, and getting it wrong shows July hours to
      // someone standing at the counter in late August.
      expect(currentSeason(DateTime(2026, 8, 21)), 'summer');
      expect(currentSeason(DateTime(2026, 8, 22)), 'fall');
    });

    test('summer is June through to the changeover', () {
      expect(currentSeason(DateTime(2026, 5, 31)), 'fall');
      expect(currentSeason(DateTime(2026, 6, 1)), 'summer');
      expect(currentSeason(DateTime(2026, 7, 15)), 'summer');
    });

    test('term time is fall', () {
      for (final month in [9, 10, 11, 12, 1, 2, 3, 4, 5]) {
        expect(currentSeason(DateTime(2026, month, 10)), 'fall',
            reason: 'month $month');
      }
    });
  });

  test('campus fields differ from a UTC instant by a real offset', () {
    // Sanity check on the helper both fixes lean on: 03:00 UTC is the previous
    // evening on campus, which is the whole reason the device clock is wrong.
    final instant = DateTime.utc(2026, 9, 3, 3, 0);
    final fields = CampusTime.fieldsOf(instant);
    expect(fields.day, 2);
    expect(fields.hour, 23);
  });
}
