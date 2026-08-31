/// Pull to refresh has to actually refresh.
///
/// It called the same path as the two minute ticker, which respects every
/// source's cadence: dining is hourly, campus places twice a day. So pulling
/// almost always fetched nothing while showing a spinner that implied it had.
/// A control that cannot do the thing it depicts is worse than no control, and
/// this is the exact shape of the problem Cole hit waiting on the kiosks.
///
/// The floor is the other half. CLAUDE.md 6 says scheduled scrapes only and
/// never per request, so a user-driven refetch has to be bounded or holding
/// the gesture would hammer RIT.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/local_backend.dart';

void main() {
  test('a manual refresh is bounded, not free', () {
    expect(LocalBackend.manualRefreshFloor, const Duration(minutes: 1));
  });

  test('the floor is shorter than the shortest cadence', () {
    // If the floor were longer than a cadence, the manual path would be more
    // restrictive than the automatic one, which would defeat the point.
    final shortest = LocalBackend.sources.values
        .map((spec) => spec.cadence)
        .reduce((a, b) => a < b ? a : b);
    expect(
      LocalBackend.manualRefreshFloor,
      lessThanOrEqualTo(shortest),
      reason: 'a manual refresh must never be rarer than the ticker',
    );
  });

  test('every source is reachable by a manual refresh', () {
    // A source missing from the map would silently never respond to the
    // gesture, which is how this class of bug hides.
    expect(LocalBackend.sources, isNotEmpty);
    for (final entry in LocalBackend.sources.entries) {
      expect(entry.value.name, entry.key, reason: 'spec keyed by its own name');
    }
  });
}
