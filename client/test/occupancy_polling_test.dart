/// The occupancy poll list, which is what keeps this feature polite.
///
/// Only 5 of 24 dining locations publish occupancy. Polling all 24 every five
/// minutes is 6,912 requests a day for 5 useful answers. The backend kept an
/// `occupancy_probe` table to avoid that and this is the same idea, so it is
/// worth a test: getting it wrong is invisible in the UI and rude upstream.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/maps_occupancy.dart';

void main() {
  final now = DateTime.utc(2026, 8, 30, 12);
  String ago(Duration d) => now.subtract(d).toIso8601String();

  test('probes only a budget of unknowns on the first run', () {
    // A cold start knows nothing. Probing all of them is 226 KB each, which is
    // slow enough that the app can close before the snapshot is written.
    expect(
      occupancyPollList(List.generate(24, (i) => i + 1), const {}, now),
      [1, 2, 3, 4, 5, 6],
    );
  });

  test('picks up where the last run stopped, so discovery finishes', () {
    final probes = {
      for (var i = 1; i <= 6; i++)
        '$i': {'has_density': false, 'probed_at': ago(const Duration(minutes: 5))},
    };
    expect(
      occupancyPollList(List.generate(24, (i) => i + 1), probes, now),
      [7, 8, 9, 10, 11, 12],
    );
  });

  test('always polls a known sensor, budget or not', () {
    final probes = {
      '20': {'has_density': true, 'probed_at': ago(const Duration(minutes: 5))},
    };
    final due = occupancyPollList(List.generate(24, (i) => i + 1), probes, now);
    expect(due.first, 20, reason: 'the sensors are the actual feature');
    expect(due.length, 7, reason: 'one known plus a budget of six probes');
  });

  test('then polls only the ones with a sensor', () {
    final probes = {
      '1': {'has_density': true, 'probed_at': ago(const Duration(minutes: 5))},
      '2': {'has_density': false, 'probed_at': ago(const Duration(minutes: 5))},
      '3': {'has_density': false, 'probed_at': ago(const Duration(minutes: 5))},
    };
    expect(occupancyPollList([1, 2, 3], probes, now), [1]);
  });

  test('rechecks a location that reported no sensor, but only rarely', () {
    final probes = {
      '1': {'has_density': false, 'probed_at': ago(const Duration(hours: 11))},
      '2': {'has_density': false, 'probed_at': ago(const Duration(hours: 13))},
    };
    // 11 hours is not yet due, 13 is. RIT should not be asked 24 times an hour
    // about a location that has told us 19 times it has no sensor.
    expect(occupancyPollList([1, 2], probes, now), [2]);
  });

  test('recovers from a probe with an unreadable timestamp', () {
    final probes = {
      '1': {'has_density': false, 'probed_at': 'not a date'},
    };
    expect(occupancyPollList([1], probes, now), [1]);
  });

  test('a new location appearing upstream is probed', () {
    final probes = {
      '1': {'has_density': false, 'probed_at': ago(const Duration(minutes: 1))},
    };
    expect(occupancyPollList([1, 99], probes, now), [99]);
  });
}
