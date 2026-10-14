/// Food truck source: parse, three states, fallback, season, year inference, request.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tigerhub/data/local_backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/drupal_events.dart';
import 'package:tigerhub/data/sources/food_trucks.dart';
import 'package:tigerhub/data/upstream.dart';

void main() {
  final page = File('test/fixtures/food_trucks.html').readAsStringSync();
  final oct14 = DateTime(2026, 10, 14);

  // empty schedule: keep the heading and container, drop every slot
  final emptyPage = () {
    final heading = RegExp(r'<h2[^>]*>\s*Current Schedule\s*</h2>').firstMatch(page)!;
    final to = page.indexOf('id="all-participating-trucks"');
    return '${page.substring(0, heading.end)}<div class="row"></div><a ${page.substring(to)}';
  }();

  final noStructure = page
      .replaceAll('Current Schedule', 'Upcoming')
      .replaceAll('id="current-schedule"', '');

  Map<String, dynamic> rodeoSnapshot() {
    final raw = jsonDecode(File('test/fixtures/drupal_truck.json').readAsStringSync());
    return {'events': parseDrupal(raw['data'] as List<dynamic>)};
  }

  Upstream upstreamReturning(String body, {void Function(http.BaseRequest)? seen}) =>
      Upstream(
        client: MockClient((request) async {
          seen?.call(request);
          return http.Response.bytes(
            utf8.encode(body),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
        maxRetries: 1,
      );

  setUp(() => RitClock.pin(DateTime.utc(2026, 10, 14, 16)));
  tearDown(RitClock.reset);

  group('parse', () {
    test('real page gives 6 slots, 3 Friday and 3 Saturday', () {
      final parsed = parseFoodTrucksHtml(page, oct14)!;
      final trucks = (parsed['trucks'] as List).cast<Map<String, dynamic>>();

      expect(trucks, hasLength(6));
      expect(trucks.where((t) => t['date'] == '2026-10-16'), hasLength(3));
      expect(trucks.where((t) => t['date'] == '2026-10-17'), hasLength(3));
      expect(parsed['origin'], 'html');
    });

    test('slot fields come through', () {
      final parsed = parseFoodTrucksHtml(page, oct14)!;
      final first = (parsed['trucks'] as List).first as Map<String, dynamic>;

      expect(first['name'], 'Bubble Waffle Bus');
      expect(first['blurb'], 'Delicious ice cream sundaes on bubble waffles!');
      expect(first['time_text'], '5pm - 8pm');
      expect(first['starts_at'], '2026-10-16T17:00:00-04:00');
      expect(first['ends_at'], '2026-10-16T20:00:00-04:00');
      expect(first['location'], 'Student Alumni Union');
      expect(first['location_url'], 'https://maps.rit.edu/details/1020');
      expect(first['website'], contains('facebook.com'));
    });

    test('half hours and entities decode', () {
      final parsed = parseFoodTrucksHtml(page, oct14)!;
      final apple = (parsed['trucks'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((t) => (t['name'] as String).startsWith('Schutt'));

      expect(apple['name'], "Schutt's Apple Mill");
      expect(apple['starts_at'], '2026-10-17T16:30:00-04:00');
      expect(apple['ends_at'], '2026-10-17T18:30:00-04:00');
    });

    test('roster comes from All Participating Trucks', () {
      final roster = (parseFoodTrucksHtml(page, oct14)!['roster'] as List)
          .cast<Map<String, dynamic>>();

      expect(roster, hasLength(20));
      expect(roster.map((r) => r['name']), contains('Bento Stop ROC'));
    });

    test('heading and container with no slots is empty, not a failure', () {
      final parsed = parseFoodTrucksHtml(emptyPage, oct14);

      expect(parsed, isNotNull);
      expect(parsed!['trucks'], isEmpty);
      expect(parsed['roster'], isNotEmpty);
    });

    test('missing container is a parse failure', () {
      expect(parseFoodTrucksHtml(noStructure, oct14), isNull);
      expect(parseFoodTrucksHtml('<html></html>', oct14), isNull);
    });

    test('date markers with unreadable slots is a parse failure', () {
      final broken = page.replaceAll('font-weight-medium h4', 'renamed');
      expect(parseFoodTrucksHtml(broken, oct14), isNull);
    });
  });

  group('season', () {
    test('read from the page text', () {
      expect(foodTruckSeasonMonths(page), {4, 8, 9, 10});
    });

    test('a range can wrap the year end', () {
      expect(
        foodTruckSeasonMonths('typically November through February and May'),
        {11, 12, 1, 2, 5},
      );
    });

    test('falls back to the default when the page does not say', () {
      expect(foodTruckSeasonMonths('<p>nothing here</p>'), defaultFoodTruckSeasonMonths);
      expect(foodTruckSeasonMonths(null), defaultFoodTruckSeasonMonths);
    });

    test('in season Aug-Oct and April only', () {
      bool at(int month) =>
          isFoodTruckSeason(DateTime(2026, month, 15), defaultFoodTruckSeasonMonths);

      expect([for (var m = 1; m <= 12; m++) if (at(m)) m], [4, 8, 9, 10]);
    });
  });

  group('year inference', () {
    test('December campus date, January slot is next year', () {
      expect(inferTruckDate(1, 2, DateTime(2026, 12, 28)), DateTime.utc(2027, 1, 2));
    });

    test('January campus date, December slot is last year', () {
      expect(inferTruckDate(12, 30, DateTime(2027, 1, 3)), DateTime.utc(2026, 12, 30));
    });

    test('same year stays in the same year', () {
      expect(inferTruckDate(10, 16, DateTime(2026, 10, 14)), DateTime.utc(2026, 10, 16));
    });

    test('feb 29 resolves to a leap year or nothing', () {
      expect(inferTruckDate(2, 29, DateTime(2027, 12, 1)), DateTime.utc(2028, 2, 29));
    });

    test('parsed slots roll over with the campus date', () {
      final lateDec = page.replaceAll('Oct 16', 'Jan 1').replaceAll('Oct 17', 'Jan 2');
      final parsed = parseFoodTrucksHtml(lateDec, DateTime(2026, 12, 29))!;
      final dates = {for (final t in parsed['trucks'] as List) t['date']};

      expect(dates, {'2027-01-01', '2027-01-02'});
    });
  });

  group('states', () {
    Map<String, dynamic> snapshot(List<Map<String, dynamic>> trucks, {String origin = 'html'}) => {
      'trucks': trucks,
      'roster': <Map<String, dynamic>>[],
      'season_months': [4, 8, 9, 10],
      'origin': origin,
    };

    test('trucks', () {
      final view = foodTruckView(parseFoodTrucksHtml(page, oct14), oct14);

      expect(view.state, FoodTruckState.trucks);
      expect(view.hidden, isFalse);
      expect(view.trucks, hasLength(6));
    });

    test('empty in season shows a line', () {
      final view = foodTruckView(parseFoodTrucksHtml(emptyPage, oct14), oct14);

      expect(view.state, FoodTruckState.empty);
      expect(view.inSeason, isTrue);
      expect(view.hidden, isFalse);
    });

    test('empty off season hides the group', () {
      final january = DateTime(2027, 1, 20);
      final view = foodTruckView(parseFoodTrucksHtml(emptyPage, january), january);

      expect(view.state, FoodTruckState.empty);
      expect(view.inSeason, isFalse);
      expect(view.hidden, isTrue);
    });

    test('unavailable is its own state and hides', () {
      final view = foodTruckView(unavailableFoodTrucks(), oct14);

      expect(view.state, FoodTruckState.unavailable);
      expect(view.hidden, isTrue);
      expect(foodTruckView(null, oct14).state, FoodTruckState.unavailable);
    });

    test('a cached snapshot drops slots before today', () {
      final view = foodTruckView(parseFoodTrucksHtml(page, oct14), DateTime(2026, 10, 17));

      expect(view.trucks, hasLength(3));
      expect(foodTruckView(parseFoodTrucksHtml(page, oct14), DateTime(2026, 10, 18)).state, FoodTruckState.empty);
    });

    test('off season snapshot with trucks still shows them', () {
      final january = DateTime(2027, 1, 20);
      final view = foodTruckView(snapshot([{'date': '2027-01-21', 'starts_at': null}]), january);

      expect(view.state, FoodTruckState.trucks);
      expect(view.hidden, isFalse);
    });
  });

  group('scrape and fallback', () {
    test('good page uses the html', () async {
      final result = await scrapeFoodTrucks(upstreamReturning(page), () async => null);
      expect(result['origin'], 'html');
      expect(result['trucks'], hasLength(6));
    });

    test('parse failure falls back to drupal rodeo events', () async {
      final result = await scrapeFoodTrucks(upstreamReturning(noStructure), () async => rodeoSnapshot());
      final trucks = (result['trucks'] as List).cast<Map<String, dynamic>>();

      expect(result['origin'], 'drupal');
      expect(trucks, hasLength(2));
      expect(trucks.first['name'], 'Food Truck Rodeo');
      expect(trucks.first['location'], 'SAU');
      expect(trucks.first['date'], '2026-10-16');
      expect(trucks.first['starts_at'], '2026-10-16T17:00:00-04:00');
    });

    test('both failing is unavailable', () async {
      final result = await scrapeFoodTrucks(upstreamReturning(noStructure), () async => null);
      expect(result['origin'], 'none');
      expect(foodTruckView(result, oct14).state, FoodTruckState.unavailable);

      final noRodeo = await scrapeFoodTrucks(upstreamReturning(noStructure), () async => {'events': []});
      expect(noRodeo['origin'], 'none');
    });

    test('a network error rethrows so the old snapshot stays', () async {
      final offline = Upstream(
        client: MockClient((_) async => throw const SocketException('offline')),
        maxRetries: 1,
      );
      expect(scrapeFoodTrucks(offline, () async => rodeoSnapshot()), throwsA(isA<UpstreamError>()));
    });
  });

  group('request and cache', () {
    test('sends the full identifying user agent, no conditional headers', () async {
      http.BaseRequest? sent;
      await scrapeFoodTrucks(upstreamReturning(page, seen: (r) => sent = r), () async => null);

      expect(sent!.url.toString(), foodTrucksUrl);
      expect(sent!.headers['User-Agent'], userAgent);
      expect(sent!.headers['User-Agent'], contains(contact));
      expect(sent!.headers.keys.map((k) => k.toLowerCase()), isNot(contains('if-none-match')));
    });

    test('cached six hours and registered as a source', () {
      expect(foodTrucksCadence, const Duration(hours: 6));
      expect(LocalBackend.sources[foodTrucksSource]!.cadence, foodTrucksCadence);
    });
  });

  group('rodeo links', () {
    test('both dead aliases point at the dining page', () {
      final events = rodeoSnapshot()['events'] as List;

      expect(events, hasLength(2));
      for (final e in events) {
        expect((e as Map)['url'], 'https://www.rit.edu/dining/food-trucks');
      }
    });

    test('other aliases and explicit links are untouched', () {
      final events = parseDrupal([
        {
          'id': 'a',
          'attributes': {
            'title': 'Talk',
            'field_start_date': '2026-10-16T00:00:00-04:00',
            'path': {'alias': '/events/talk'},
          },
        },
        {
          'id': 'b',
          'attributes': {
            'title': 'Rodeo',
            'field_start_date': '2026-10-16T00:00:00-04:00',
            'field_link': {'uri': 'https://example.com/x'},
            'path': {'alias': '/events/food-truck-rodeo-schedule'},
          },
        },
      ]);

      expect(events[0]['url'], 'https://www.rit.edu/events/talk');
      expect(events[1]['url'], 'https://example.com/x');
    });
  });
}
