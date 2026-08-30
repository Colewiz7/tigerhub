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

  test('probes everything unknown on the first run', () {
    // Discovery is a one time cost and the run is checkpointed after every
    // location, so paying it at once beats dragging it across twenty minutes
    // of five minute cycles while the app can show no occupancy at all.
    expect(
      occupancyPollList(List.generate(24, (i) => i + 1), const {}, now),
      List.generate(24, (i) => i + 1),
    );
  });

  test('resumes discovery rather than repeating it', () {
    final probes = {
      for (var i = 1; i <= 6; i++)
        '$i': {'has_density': false, 'probed_at': ago(const Duration(minutes: 5))},
    };
    expect(
      occupancyPollList(List.generate(10, (i) => i + 1), probes, now),
      [7, 8, 9, 10],
    );
  });

  test('polls known sensors first, since those are what the UI wants', () {
    final probes = {
      '20': {'has_density': true, 'probed_at': ago(const Duration(minutes: 5))},
    };
    final due = occupancyPollList([1, 2, 20], probes, now);
    expect(due.first, 20, reason: 'the sensors are the actual feature');
  });

  test('caps speculative rechecks, which are almost always wasted', () {
    final probes = {
      for (var i = 1; i <= 24; i++)
        '$i': {'has_density': false, 'probed_at': ago(const Duration(hours: 13))},
    };
    expect(
      occupancyPollList(List.generate(24, (i) => i + 1), probes, now).length,
      6,
      reason: 'a location without a sensor yesterday still has none today',
    );
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
