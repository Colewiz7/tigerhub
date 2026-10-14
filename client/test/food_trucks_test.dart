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
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/upstream.dart';

void main() {
  final page = File('test/fixtures/food_trucks.html').readAsStringSync();
  final oct14 = DateTime(2026, 10, 14);

  const colStart = '<div class="col-12 col-sm-6 col-md-4 col-lg-3 mb-5">';

  // empty schedule: keep the heading and view wrapper, drop the six slots
  final emptyPage = () {
    final from = page.indexOf(colStart);
    final lastLink = page.lastIndexOf('Visit Website</a>', page.indexOf('id="all-participating-trucks"'));
    final to = page.indexOf('</div>', page.indexOf('</div>', lastLink) + 1) + '</div>'.length;
    return page.substring(0, from) + page.substring(to);
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

  final drupalJson = File('test/fixtures/drupal_truck.json').readAsStringSync();
  const noEvents = '{"data":[],"links":{}}';

  // a string body is a 200, null is a dead network
  Upstream routed({String? pageBody, String? drupalBody, List<Uri>? log}) => Upstream(
    client: MockClient((request) async {
      log?.add(request.url);
      final body = request.url.path.contains('jsonapi') ? drupalBody : pageBody;
      if (body == null) throw const SocketException('offline');
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }),
    maxRetries: 1,
  );

  int pageHits(List<Uri> log) => log.where((u) => u.path == '/dining/food-trucks').length;

  setUp(() {
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
    foodTruckPacer.reset();
  });
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

    test('an explicit short no-trucks note in the view is empty', () {
      final noted = emptyPage.replaceFirst(
        'paragraph--type--embed-view paragraph--view-mode--default">',
        'paragraph--type--embed-view paragraph--view-mode--default"><p>No food trucks scheduled.</p>',
      );
      expect(noted, isNot(emptyPage));
      expect(parseFoodTrucksHtml(noted, oct14)!['trucks'], isEmpty);
    });

    test('other text in an otherwise empty view is not proof of empty', () {
      final chatty = emptyPage.replaceFirst(
        'paragraph--type--embed-view paragraph--view-mode--default">',
        'paragraph--type--embed-view paragraph--view-mode--default"><p>Bubble Waffle Bus, Friday</p>',
      );
      expect(parseFoodTrucksHtml(chatty, oct14), isNull);
    });

    test('the view wrapper gone is a failure, not empty', () {
      final bare = emptyPage.replaceAll('paragraph--type--embed-view', 'paragraph--type--other');
      expect(parseFoodTrucksHtml(bare, oct14), isNull);
    });

    group('wrapper name must be a real element class', () {
      const token = 'paragraph--type--embed-view';

      // no real wrapper left, only the given junk right after the heading
      String withJunk(String junk) {
        final bare = emptyPage.replaceAll(token, 'paragraph--type--other');
        final heading = RegExp(r'<h2[^>]*>\s*Current Schedule\s*</h2>').firstMatch(bare)!;
        return bare.substring(0, heading.end) + junk + bare.substring(heading.end);
      }

      test('only inside an HTML comment', () {
        expect(parseFoodTrucksHtml(withJunk('<!-- $token -->'), oct14), isNull);
      });

      test('only inside a script', () {
        expect(parseFoodTrucksHtml(withJunk('<script>var c = "$token";</script>'), oct14), isNull);
      });

      test('only inside a style', () {
        expect(parseFoodTrucksHtml(withJunk('<style>.$token {}</style>'), oct14), isNull);
      });

      test('only inside another attribute value', () {
        expect(parseFoodTrucksHtml(withJunk('<div data-x="class=\'$token\'"></div>'), oct14), isNull);
        expect(parseFoodTrucksHtml(withJunk('<div title="$token"></div>'), oct14), isNull);
        expect(parseFoodTrucksHtml(withJunk('<div data-class="$token"></div>'), oct14), isNull);
      });

      test('only as text', () {
        expect(parseFoodTrucksHtml(withJunk('<p>$token</p>'), oct14), isNull);
      });

      test('only as part of a longer class token', () {
        expect(parseFoodTrucksHtml(withJunk('<div class="x-$token-2"></div>'), oct14), isNull);
      });

      test('a real wrapper alongside the junk still counts', () {
        expect(parseFoodTrucksHtml('<!-- $token -->$emptyPage', oct14)!['trucks'], isEmpty);
      });

      // junk placed at the end of the schedule, after the real wrapper
      String afterWrapper(String junk) {
        final cut = emptyPage.lastIndexOf('<', emptyPage.indexOf('id="all-participating-trucks"'));
        return emptyPage.substring(0, cut) + junk + emptyPage.substring(cut);
      }

      String beforeWrapper(String junk) {
        final heading = RegExp(r'<h2[^>]*>\s*Current Schedule\s*</h2>').firstMatch(emptyPage)!;
        return emptyPage.substring(0, heading.end) + junk + emptyPage.substring(heading.end);
      }

      const wrapper = '<div class="$token"></div>';

      test('unterminated comment hiding a wrapper after visible text', () {
        expect(parseFoodTrucksHtml(withJunk('No trucks scheduled <!-- <div class="$token">'), oct14), isNull);
      });

      test('unterminated comment before or after the real wrapper', () {
        expect(parseFoodTrucksHtml(beforeWrapper('<!-- '), oct14), isNull);
        expect(parseFoodTrucksHtml(afterWrapper('<!-- tail'), oct14), isNull);
      });

      test('unclosed script after visible text or a real wrapper', () {
        expect(parseFoodTrucksHtml(withJunk('No trucks scheduled <script> <div class="$token">'), oct14), isNull);
        expect(parseFoodTrucksHtml(afterWrapper('<script>var a = 1;'), oct14), isNull);
        expect(parseFoodTrucksHtml(afterWrapper('<style>.a {'), oct14), isNull);
      });

      test('closed comment, script and style around a real wrapper are fine', () {
        final tidy = beforeWrapper('<!-- note --><script>var a = "<b>";</script><style>.a {}</style>');
        expect(parseFoodTrucksHtml(tidy, oct14)!['trucks'], isEmpty);
      });

      test('CDATA is not understood', () {
        expect(parseFoodTrucksHtml(withJunk('<![CDATA[ <div class="$token"></div> ]]>'), oct14), isNull);
        expect(parseFoodTrucksHtml(afterWrapper('<![CDATA[ x ]]>'), oct14), isNull);
      });

      test('a wrapper inside template or noscript is inert', () {
        expect(parseFoodTrucksHtml(withJunk('<template>$wrapper</template>'), oct14), isNull);
        expect(parseFoodTrucksHtml(withJunk('<noscript>$wrapper</noscript>'), oct14), isNull);
        expect(parseFoodTrucksHtml(afterWrapper('<template><p>x</p></template>'), oct14), isNull);
        expect(parseFoodTrucksHtml(afterWrapper('<noscript>x</noscript>'), oct14), isNull);
      });

      test('iframe, object, svg and other unknown elements fail closed', () {
        for (final junk in ['<iframe></iframe>', '<object></object>', '<svg></svg>', '<img src="x">', '<a href="x"></a>', '<x-slot></x-slot>']) {
          expect(parseFoodTrucksHtml(afterWrapper(junk), oct14), isNull, reason: junk);
        }
      });

      test('duplicate class attributes: the first one wins, in both orders', () {
        expect(parseFoodTrucksHtml(withJunk('<div class="other" CLASS="$token"></div>'), oct14), isNull);
        expect(parseFoodTrucksHtml(withJunk('<div class="$token" class="other"></div>'), oct14)!['trucks'], isEmpty);
        expect(parseFoodTrucksHtml(withJunk('<div CLASS="$token" class="other"></div>'), oct14)!['trucks'], isEmpty);
      });

      test('quoting and unquoted values are read', () {
        expect(parseFoodTrucksHtml(withJunk("<div class='a $token b'></div>"), oct14)!['trucks'], isEmpty);
        expect(parseFoodTrucksHtml(withJunk('<div class=$token></div>'), oct14)!['trucks'], isEmpty);
        expect(parseFoodTrucksHtml(withJunk('<div class="$token'), oct14), isNull);
      });

      test('a wrapper missing its close tag is a failure', () {
        // the page slice ends in ancestor close tags, so these run on the bare scanner
        expect(isEmptySchedule('<div class="$token">', false), isFalse);
        expect(isEmptySchedule('<div class="$token"><div></div>', false), isFalse);
        expect(isEmptySchedule('<div class="$token"><span></div>', false), isFalse);
        expect(isEmptySchedule('<div class="$token"></div>', false), isTrue);
        expect(parseFoodTrucksHtml(withJunk('<div class="$token"><span></div>'), oct14), isNull);
      });

      test('a synthetic empty wrapper, with and without a note, is empty', () {
        expect(parseFoodTrucksHtml(withJunk(wrapper), oct14)!['trucks'], isEmpty);
        expect(
          parseFoodTrucksHtml(withJunk('<div class="$token"><p>No trucks scheduled</p></div>'), oct14)!['trucks'],
          isEmpty,
        );
      });

      test('text outside the wrapper still counts', () {
        expect(parseFoodTrucksHtml(withJunk('Bubble Waffle Bus $wrapper'), oct14), isNull);
        expect(parseFoodTrucksHtml(withJunk('$wrapper Bubble Waffle Bus'), oct14), isNull);
      });

      test('real wrapper, empty, is empty', () {
        expect(parseFoodTrucksHtml(emptyPage, oct14)!['trucks'], isEmpty);
      });

      test('real wrapper with a note is empty', () {
        final noted = emptyPage.replaceFirst('$token paragraph--view-mode--default">', '$token paragraph--view-mode--default"><p>No food trucks scheduled.</p>');
        expect(noted, isNot(emptyPage));
        expect(parseFoodTrucksHtml(noted, oct14)!['trucks'], isEmpty);
      });
    });

    test('mutation: slot date class renamed, heading and container kept', () {
      expect(parseFoodTrucksHtml(page.replaceAll('h5 mb-3', 'h5 mb-4'), oct14), isNull);
    });

    test('mutation: truck name class renamed', () {
      expect(parseFoodTrucksHtml(page.replaceAll('font-weight-medium h4', 'h4 fw'), oct14), isNull);
    });

    test('mutation: slot markup restructured into other tags', () {
      final moved = page
          .replaceAll('<div class="h5 mb-3">', '<p class="when">')
          .replaceAll(colStart, '<section class="slot">');
      expect(parseFoodTrucksHtml(moved, oct14), isNull);

      final table = page.replaceAll(colStart, '<table><tr><td>').replaceAll('font-weight-medium h4', 'cell');
      expect(parseFoodTrucksHtml(table, oct14), isNull);
    });

    test('mutation: date text present but no truck names', () {
      final nameless = page.replaceAll(RegExp(r'<div class="font-weight-medium h4[^"]*">.*?</div>', dotAll: true), '');
      expect(parseFoodTrucksHtml(nameless, oct14), isNull);
    });

    test('mutation: truck names present but dates unreadable', () {
      final dateless = page.replaceAll(RegExp(r'(Friday|Saturday), Oct \d+'), 'To be announced');
      expect(parseFoodTrucksHtml(dateless, oct14), isNull);
    });

    test('a display:none slot is left out', () {
      final hidden = page.replaceFirst(colStart, '<div class="col-12 col-sm-6 col-md-4 col-lg-3 mb-5" style="display: none">');
      final trucks = (parseFoodTrucksHtml(hidden, oct14)!['trucks'] as List).cast<Map<String, dynamic>>();

      expect(trucks, hasLength(5));
      expect(trucks.map((t) => t['name']), isNot(contains('Bubble Waffle Bus')));
    });

    test('every slot hidden is a failure, not empty', () {
      final hidden = page.replaceAll(colStart, '<div class="col-12 col-sm-6 col-md-4 col-lg-3 mb-5" style="display:none">');
      expect(parseFoodTrucksHtml(hidden, oct14), isNull);
    });

    test('identical slots collapse to one', () {
      final first = page.indexOf(colStart);
      final second = page.indexOf(colStart, first + 1);
      final doubled = page.substring(0, second) + page.substring(first, second) + page.substring(second);

      expect((parseFoodTrucksHtml(doubled, oct14)!['trucks'] as List), hasLength(6));
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

    test('Dec 31 and Jan 1 resolve across the year boundary both ways', () {
      expect(inferTruckDate(1, 1, DateTime(2026, 12, 31)), DateTime.utc(2027, 1, 1));
      expect(inferTruckDate(12, 31, DateTime(2027, 1, 1)), DateTime.utc(2026, 12, 31));
      expect(inferTruckDate(12, 31, DateTime(2026, 12, 31)), DateTime.utc(2026, 12, 31));
      expect(inferTruckDate(1, 1, DateTime(2027, 1, 1)), DateTime.utc(2027, 1, 1));
    });

    test('exactly 6 months ahead is in the window', () {
      expect(inferTruckDate(4, 14, DateTime(2026, 10, 14)), DateTime.utc(2027, 4, 14));
    });

    test('exactly 6 months back is in the window', () {
      expect(inferTruckDate(10, 14, DateTime(2027, 4, 14)), DateTime.utc(2026, 10, 14));
    });

    test('one day past 6 months on one side, the other side takes it', () {
      expect(inferTruckDate(4, 15, DateTime(2026, 10, 14)), DateTime.utc(2026, 4, 15));
      expect(inferTruckDate(10, 13, DateTime(2027, 4, 14)), DateTime.utc(2027, 10, 13));
      expect(inferTruckDate(4, 13, DateTime(2026, 10, 14)), DateTime.utc(2027, 4, 13));
    });

    test('month end clamps when the window edge has no such day', () {
      expect(inferTruckDate(2, 28, DateTime(2026, 8, 31)), DateTime.utc(2027, 2, 28));
      expect(inferTruckDate(8, 31, DateTime(2027, 2, 28)), DateTime.utc(2026, 8, 31));
    });

    test('feb 29 farther than 6 months from any leap day is rejected', () {
      expect(inferTruckDate(2, 29, DateTime(2026, 10, 14)), isNull);
      expect(inferTruckDate(2, 29, DateTime(2027, 8, 1)), isNull);
      expect(inferTruckDate(2, 29, DateTime(2028, 1, 10)), DateTime.utc(2028, 2, 29));
      expect(inferTruckDate(2, 29, DateTime(2027, 12, 1)), DateTime.utc(2028, 2, 29));
    });

    test('an impossible date is rejected, not coerced', () {
      expect(inferTruckDate(2, 30, DateTime(2026, 10, 14)), isNull);
      expect(inferTruckDate(4, 31, DateTime(2026, 10, 14)), isNull);
    });

    test('a slot the window rejects is dropped from the parse', () {
      final leap = page.replaceAll('Oct 16', 'Feb 29');
      final parsed = parseFoodTrucksHtml(leap, DateTime(2026, 10, 14))!;

      expect((parsed['trucks'] as List).map((t) => t['date']).toSet(), {'2026-10-17'});
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

    test('parse failure with a cold drupal cache fetches the rodeo events', () async {
      final log = <Uri>[];
      final result = await scrapeFoodTrucks(
        routed(pageBody: noStructure, drupalBody: drupalJson, log: log),
        () async => null,
      );

      expect(result['origin'], 'drupal');
      expect(result['trucks'], hasLength(2));
      final drupal = log.singleWhere((u) => u.path.contains('jsonapi'));
      expect(drupal.queryParameters['filter[title]'], rodeoTitle);
    });

    test('a warm drupal cache is used without another request', () async {
      final log = <Uri>[];
      final result = await scrapeFoodTrucks(
        routed(pageBody: noStructure, drupalBody: null, log: log),
        () async => rodeoSnapshot(),
      );

      expect(result['origin'], 'drupal');
      expect(log.where((u) => u.path.contains('jsonapi')), isEmpty);
    });

    test('network error on the page with a cold cache still uses the fallback', () async {
      final result = await scrapeFoodTrucks(
        routed(pageBody: null, drupalBody: drupalJson),
        () async => null,
      );

      expect(result['origin'], 'drupal');
      expect(result['trucks'], hasLength(2));
    });

    test('network error on the page with a warm cache uses the fallback', () async {
      final result = await scrapeFoodTrucks(
        routed(pageBody: null, drupalBody: null),
        () async => rodeoSnapshot(),
      );
      expect(result['origin'], 'drupal');
    });

    test('both failing by parse is a stored unavailable', () async {
      final result = await scrapeFoodTrucks(
        routed(pageBody: noStructure, drupalBody: noEvents),
        () async => null,
      );

      expect(result['origin'], 'none');
      expect(foodTruckView(result, oct14).state, FoodTruckState.unavailable);

      foodTruckPacer.reset();
      final warm = await scrapeFoodTrucks(
        routed(pageBody: noStructure, drupalBody: noEvents),
        () async => {'events': []},
      );
      expect(warm['origin'], 'none');
    });

    test('both failing by network rethrows so the old snapshot stays', () async {
      expect(
        scrapeFoodTrucks(routed(pageBody: null, drupalBody: null), () async => null),
        throwsA(isA<UpstreamError>()),
      );
    });

    test('a fetch error on one side with nothing from the other rethrows', () async {
      expect(
        scrapeFoodTrucks(routed(pageBody: noStructure, drupalBody: null), () async => null),
        throwsA(isA<UpstreamError>()),
      );
      foodTruckPacer.reset();
      expect(
        scrapeFoodTrucks(routed(pageBody: null, drupalBody: noEvents), () async => null),
        throwsA(isA<UpstreamError>()),
      );
    });

    test('a past rodeo event is not a fallback', () async {
      final past = rodeoSnapshot();
      RitClock.pin(DateTime.utc(2026, 10, 20, 16));
      final result = await scrapeFoodTrucks(
        routed(pageBody: noStructure, drupalBody: noEvents),
        () async => past,
      );
      expect(result['origin'], 'none');
    });

    test('the registered source falls back on a cold cache end to end', () async {
      StaticConfig.overrideForTesting({});
      final result = await LocalBackend.sources[foodTrucksSource]!.scrape(
        ScrapeContext(
          http: routed(pageBody: noStructure, drupalBody: drupalJson),
          previous: null,
          save: (_) async {},
          snapshotOf: (_) async => null,
          config: StaticConfig.instance,
        ),
      );
      expect(result['origin'], 'drupal');
    });
  });

  group('pacing', () {
    late DateTime clock;
    late FoodTruckPacer pacer;
    late List<Uri> log;

    setUp(() {
      clock = DateTime.utc(2026, 10, 14, 12);
      pacer = FoodTruckPacer(clock: () => clock);
      log = [];
    });

    Future<Map<String, dynamic>> run({String? pageBody, Map<String, dynamic>? previous, String? drupalBody}) =>
        scrapeFoodTrucks(
          routed(pageBody: pageBody, drupalBody: drupalBody, log: log),
          () async => null,
          previous: previous,
          pacer: pacer,
        );

    Future<bool> fetches({String? pageBody, Map<String, dynamic>? previous}) async {
      final before = pageHits(log);
      try {
        await run(pageBody: pageBody, previous: previous);
      } on UpstreamError {
        // refused or failed, the hit count says which
      }
      return pageHits(log) > before;
    }

    test('after a clean read nothing fetches until 6 hours', () async {
      final first = await run(pageBody: page);
      expect(first['fetched_at'], clock.toIso8601String());

      for (final wait in [const Duration(minutes: 1), const Duration(hours: 5, minutes: 59)]) {
        clock = DateTime.utc(2026, 10, 14, 12).add(wait);
        expect(await fetches(pageBody: page, previous: first), isFalse, reason: '$wait');
      }

      clock = DateTime.utc(2026, 10, 14, 12, 0).add(const Duration(hours: 6, minutes: 1));
      expect(await fetches(pageBody: page, previous: first), isTrue);
    });

    test('after a network failure the retry waits 5 minutes', () async {
      expect(await fetches(pageBody: null), isTrue);

      clock = clock.add(const Duration(minutes: 1));
      expect(await fetches(pageBody: page), isFalse);
      clock = clock.add(const Duration(minutes: 3, seconds: 59));
      expect(await fetches(pageBody: page), isFalse);
      clock = clock.add(const Duration(seconds: 2));
      expect(await fetches(pageBody: page), isTrue);
    });

    test('a stored unavailable or fallback result retries after 5 minutes too', () async {
      final unavailable = await run(pageBody: noStructure, drupalBody: noEvents);
      expect(unavailable['origin'], 'none');

      clock = clock.add(const Duration(minutes: 1));
      expect(await fetches(pageBody: page, previous: unavailable), isFalse);
      clock = clock.add(const Duration(minutes: 4, seconds: 1));
      expect(await fetches(pageBody: page, previous: unavailable), isTrue);
    });

    test('a restart keeps the spacing through the stored fetched_at', () async {
      final stored = {'origin': 'html', 'fetched_at': clock.subtract(const Duration(hours: 5)).toIso8601String()};
      expect(await fetches(pageBody: page, previous: stored), isFalse);

      final old = {'origin': 'html', 'fetched_at': clock.subtract(const Duration(hours: 7)).toIso8601String()};
      expect(await fetches(pageBody: page, previous: old), isTrue);
    });

    test('a snapshot without fetched_at, from the first version, does not block', () async {
      expect(await fetches(pageBody: page, previous: {'origin': 'html'}), isTrue);
    });
  });

  group('manual refresh', () {
    late Directory dir;
    late List<Uri> log;
    late LocalBackend backend;
    late JsonStore store;

    setUp(() {
      // without it every scrape throws before any request, which reads as zero fetches
      StaticConfig.overrideForTesting({});
      dir = Directory.systemTemp.createTempSync('food-trucks');
      store = JsonStore.overrideForTesting(dir);
      log = [];
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<int> refreshAfter(Duration age, {String origin = 'html'}) async {
      final stamp = DateTime.now().subtract(age);
      await store.write(foodTrucksSource, {
        'trucks': <Map<String, dynamic>>[],
        'roster': <Map<String, dynamic>>[],
        'origin': origin,
        'fetched_at': stamp.toUtc().toIso8601String(),
      });
      File('${dir.path}/${JsonStore.fileNameFor(foodTrucksSource)}').setLastModifiedSync(stamp);
      log.clear();
      // fresh backend each time, the in memory snapshot would hide the new file
      backend = LocalBackend(
        upstream: routed(pageBody: page, drupalBody: noEvents, log: log),
        store: store,
      );
      await backend.refreshNow();
      return pageHits(log);
    }

    test('pull to refresh does not refetch inside 6 hours', () async {
      expect(await refreshAfter(const Duration(minutes: 2)), 0);
    });

    test('still held at 5h59', () async {
      expect(await refreshAfter(const Duration(hours: 5, minutes: 59)), 0);
    });

    test('fetches at 6h01', () async {
      expect(await refreshAfter(const Duration(hours: 6, minutes: 1)), 1);
    });

    test('after a failed read it waits 5 minutes, not 6 hours and not 1', () async {
      expect(await refreshAfter(const Duration(minutes: 2), origin: 'none'), 0);
      expect(await refreshAfter(const Duration(minutes: 5, seconds: 1), origin: 'none'), 1);
    });
  });

  group('request and cache', () {
    test('sends the full identifying user agent, no conditional headers', () async {
      http.BaseRequest? sent;
      await scrapeFoodTrucks(upstreamReturning(page, seen: (r) => sent = r), () async => null);

      expect(sent!.url.toString(), foodTrucksUrl);
      expect(sent!.headers['User-Agent'], userAgent);
      expect(sent!.headers['User-Agent'], contains(contact));
      final sentHeaders = sent!.headers.keys.map((k) => k.toLowerCase());
      expect(sentHeaders, isNot(contains('if-none-match')));
      expect(sentHeaders, isNot(contains('if-modified-since')));
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
