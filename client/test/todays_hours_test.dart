/// What a post office service is doing right now.
///
/// The config is per service, per weekday, per season, and a service can close
/// over lunch and reopen. Reading that table to answer "can I go now" is the
/// thing this removes, so the lunch gap is the case that matters: being closed
/// at 1:15 is not the same as being done for the day, and saying so is the
/// whole point.
///
/// Times are campus wall clock, not the device's, because a post office does
/// not move when a laptop does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/todays_hours.dart';

void main() {
  // Global Village's real fall rules, from assets/config/post_offices.json.
  const weekdays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'];
  const rules = [
    HoursRule(
      days: weekdays,
      opensAt: '09:00',
      closesAt: '16:30',
      season: 'fall',
      service: 'package_pickup',
    ),
    HoursRule(
      days: ['SATURDAY'],
      opensAt: '12:00',
      closesAt: '16:00',
      season: 'fall',
      service: 'package_pickup',
    ),
    // The shipping window closes over lunch, arriving as two rules.
    HoursRule(
      days: weekdays,
      opensAt: '09:00',
      closesAt: '13:00',
      season: 'fall',
      service: 'shipping_window',
    ),
    HoursRule(
      days: weekdays,
      opensAt: '13:30',
      closesAt: '16:00',
      season: 'fall',
      service: 'shipping_window',
    ),
  ];

  // 2026-09-02 is a Wednesday, 2026-09-05 a Saturday, 2026-09-06 a Sunday.
  DateTime at(int day, int hour, int minute) =>
      CampusTime.wall(2026, 9, day, hour, minute);

  TodaysHours pickup(DateTime now) =>
      todaysHours(service: 'package_pickup', rules: rules, now: now);

  TodaysHours shipping(DateTime now) =>
      todaysHours(service: 'shipping_window', rules: rules, now: now);

  group('package pickup', () {
    test('open in the middle of a weekday', () {
      final today = pickup(at(2, 11, 0));
      expect(today.state, ServiceState.open);
      expect(CampusTime.format(today.closesAt!), contains('16:30'));
    });

    test('closed before it opens, and says when it will', () {
      final today = pickup(at(2, 8, 30));
      expect(today.state, ServiceState.closedUntilLater);
      expect(CampusTime.format(today.opensAt!), contains('09:00'));
    });

    test('done for the day after closing', () {
      expect(pickup(at(2, 17, 0)).state, ServiceState.closedForDay);
    });

    test('shut on a Sunday, which is not the same as being between spans', () {
      final today = pickup(at(6, 12, 0));
      expect(today.state, ServiceState.closedForDay);
      expect(today.spans, isEmpty);
    });

    test('Saturday runs its own shorter hours', () {
      expect(pickup(at(5, 11, 30)).state, ServiceState.closedUntilLater);
      expect(pickup(at(5, 13, 0)).state, ServiceState.open);
      expect(pickup(at(5, 16, 30)).state, ServiceState.closedForDay);
    });
  });

  group('the shipping window closes over lunch', () {
    test('open in the morning span', () {
      final today = shipping(at(2, 10, 0));
      expect(today.state, ServiceState.open);
      expect(CampusTime.format(today.closesAt!), contains('13:00'));
    });

    test('inside the gap it is coming back, not finished', () {
      // The distinction this whole thing exists for. "Closed" alone would send
      // someone away fifteen minutes before it reopens.
      final today = shipping(at(2, 13, 15));
      expect(today.state, ServiceState.closedUntilLater);
      expect(CampusTime.format(today.opensAt!), contains('13:30'));
    });

    test('open again in the afternoon span', () {
      expect(shipping(at(2, 14, 0)).state, ServiceState.open);
    });

    test('finished after the second span', () {
      expect(shipping(at(2, 16, 30)).state, ServiceState.closedForDay);
    });

    test('both spans are reported, in order', () {
      final today = shipping(at(2, 10, 0));
      expect(today.spans.length, 2);
      expect(today.spans.first.opens.isBefore(today.spans.last.opens), isTrue);
    });
  });

  group('edges', () {
    test('the moment it opens counts as open', () {
      expect(pickup(at(2, 9, 0)).state, ServiceState.open);
    });

    test('the moment it closes counts as closed', () {
      // Half open interval: arriving exactly at closing is arriving late.
      expect(pickup(at(2, 16, 30)).state, ServiceState.closedForDay);
    });

    test('a service with no rules at all is unknown, not closed', () {
      // Claiming "closed" for something the config never described would be
      // inventing an answer.
      final today = todaysHours(
        service: 'notary',
        rules: rules,
        now: at(2, 11, 0),
      );
      expect(today.state, ServiceState.unknown);
    });

    test('unreadable times are skipped rather than crashing', () {
      const broken = [
        HoursRule(
          days: weekdays,
          opensAt: 'nonsense',
          closesAt: '16:00',
          season: 'fall',
          service: 'package_pickup',
        ),
      ];
      final today = todaysHours(
        service: 'package_pickup',
        rules: broken,
        now: at(2, 11, 0),
      );
      expect(today.state, ServiceState.closedForDay);
      expect(today.spans, isEmpty);
    });
  });

  test('services keep the order the config lists them in', () {
    // Alphabetical would put the shipping window before package pickup, which
    // is not the order anyone thinks about them in.
    expect(servicesIn(rules), ['package_pickup', 'shipping_window']);
  });
}
