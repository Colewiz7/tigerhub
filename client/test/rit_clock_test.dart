import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/widgets/freshness.dart';

/// These run in CI under several device zones (see the workflow's TZ matrix).
/// Every assertion is about the campus clock, so the answer must not depend on
/// the zone the test process happens to run in.
void main() {
  tearDown(RitClock.reset);

  test('the campus day follows New York, not the device or UTC', () {
    // 03:30 UTC on 9 Oct is 23:30 EDT on 8 Oct.
    RitClock.pin(DateTime.utc(2026, 10, 9, 3, 30));
    expect(CampusTime.wallDate(), DateTime(2026, 10, 8));
    expect(CampusTime.wallNow().hour, 23);
    // 04:00 UTC is midnight EDT: the day rolls over here, not at UTC midnight.
    RitClock.pin(DateTime.utc(2026, 10, 9, 4));
    expect(CampusTime.wallDate(), DateTime(2026, 10, 9));
  });

  test('spring forward: 02:30 on 8 Mar 2026 does not exist, 03:00 is EDT', () {
    RitClock.pin(DateTime.utc(2026, 3, 8, 6, 59)); // 01:59 EST
    expect(CampusTime.wallNow().hour, 1);
    RitClock.pin(DateTime.utc(2026, 3, 8, 7)); // jumps to 03:00 EDT
    expect(CampusTime.wallNow().hour, 3);
  });

  test('fall back: 1 Nov 2026 has two 01:00 hours', () {
    RitClock.pin(DateTime.utc(2026, 11, 1, 5, 30)); // 01:30 EDT
    expect(CampusTime.wallNow().hour, 1);
    RitClock.pin(DateTime.utc(2026, 11, 1, 6, 30)); // 01:30 EST
    expect(CampusTime.wallNow().hour, 1);
    RitClock.pin(DateTime.utc(2026, 11, 1, 7)); // 02:00 EST
    expect(CampusTime.wallNow().hour, 2);
  });

  test('an overnight span reads on the campus clock in any device zone', () {
    final opens = CampusTime.wall(2026, 10, 8, 22);
    final closes = CampusTime.wall(2026, 10, 9, 2);
    expect(formatClock(opens), '10:00 PM');
    expect(formatClock(closes), '2:00 AM');
    expect(formatClock(CampusTime.wall(2026, 10, 9)), 'midnight');
    expect(formatDayAndClock(closes), 'Fri 9 Oct, 2:00 AM');
  });
}
