/// Visiting chefs from rit.edu, and the three answers the feed can give.
///
/// TigerCenter `dining-all` returns every `menus[]` empty (24 of 24 on
/// 2026-10-14), which the old code rendered as "No visiting chefs today". The
/// failure this guards is that mix-up: a feed that could not answer must not
/// look like a quiet day. The two rit.edu fixtures are trimmed copies of the
/// live pages saved on 2026-10-14.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tigerhub/data/local_backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/rit_chefs.dart';
import 'package:tigerhub/data/sources/tigercenter.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/upstream.dart';
import 'package:tigerhub/models/api_models.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A /dining/menus whose locations list no chefs, in the structure populated
/// days use. The live fixture with every chef removed, not a bare heading.
const String emptyMenusHtml = '''
<h2><i class="fa fa-id-badge"></i> Today's Visiting Chefs</h2>
<div>
  <a href="/dining/location/ritz" class="link-with-icon see-more">
    <p class="h5 mt-0 mb-1">RITZ</p>
  </a>
  <ul>
  </ul>
</div>
<script></script>''';

/// Noon on 2026-10-14 in Rochester (EDT), the day the fixtures describe.
final DateTime today = DateTime.utc(2026, 10, 14, 16);

Map<String, dynamic> tigerCenter({bool withChef = false}) {
  final payload =
      jsonDecode(fixture('tc_dining_all_empty_menus.json'))
          as Map<String, dynamic>;
  final locations = parseDining(payload);
  if (withChef) {
    locations.firstWhere((l) => l['id'] == 21)['menus'] = [
      {'id': 7, 'name': 'Chef Ana', 'category': 'visiting chef'},
    ];
  }
  return {'service_date': '2026-10-14', 'locations': locations};
}

Map<String, dynamic> ritSnapshot({
  String? menusHtml,
  String? scheduleHtml,
  String date = '2026-10-14',
  bool todayOk = true,
  bool scheduleOk = true,
}) {
  final menus = menusHtml == null ? null : parseTodayChefs(menusHtml);
  return {
    'service_date': date,
    'today_ok': todayOk,
    'schedule_ok': scheduleOk,
    'today': menus == null
        ? null
        : {'date': date, 'found': menus.found, 'chefs': menus.chefs},
    'schedule': scheduleHtml == null ? null : parseChefSchedule(scheduleHtml),
  };
}

void main() {
  group('/dining/menus parse', () {
    final parsed = parseTodayChefs(fixture('rit_dining_menus.html'));

    test('finds every chef under Today\'s Visiting Chefs', () {
      expect(parsed.found, isTrue);
      expect(
        parsed.chefs.map((c) => c['chef_id']),
        ['23-1', '23-2', '22-1', '26-1', '26-2'],
      );
    });

    test('names, cuisine, times and locations', () {
      final first = parsed.chefs.first;
      expect(first['name'], 'KO-BQ');
      expect(first['cuisine'], 'Korean fusion cuisine');
      expect(first['start'], '11:00');
      expect(first['end'], '14:00');
      expect(first['location_id'], 23);
      expect(first['location_name'], 'The Cafe & Market at Crossroads');

      final evening = parsed.chefs[1];
      expect(evening['name'], 'Tandoor of India');
      expect(evening['start'], '16:00');
      expect(evening['end'], '19:00');

      expect(
        parsed.chefs.map((c) => c['location_name']).toSet(),
        {'The Cafe & Market at Crossroads', 'Kitchen at Brick City', 'RITZ'},
      );
      expect(parsed.chefs[2]['location_id'], 22);
    });

    test('decodes entities in names', () {
      expect(parsed.chefs[3]['name'], "D'Mangu");
      expect(parsed.chefs[3]['cuisine'], 'Native Dominican cuisine');
    });

    test('splits on the colon before the time, not the first colon', () {
      final split = splitChefText('Chef: Pasta Night: 4:30 pm - 7 pm');
      expect(split.name, 'Chef: Pasta Night');
      expect(split.start, '16:30');
      expect(split.end, '19:00');

      final noTime = splitChefText('Mystery Chef');
      expect(noTime.name, 'Mystery Chef');
      expect(noTime.start, isNull);
      expect(noTime.end, isNull);
    });

    test('a page without the heading is not found, not empty', () {
      expect(parseTodayChefs('<html><body>Maintenance</body></html>').found,
          isFalse);
    });

    test('location blocks with empty lists are a confirmed empty day', () {
      final quiet = parseTodayChefs(emptyMenusHtml);
      expect(quiet.found, isTrue);
      expect(quiet.chefs, isEmpty);
    });

    test('RIT\'s no-visiting-chefs marker is a confirmed empty day', () {
      final quiet = parseTodayChefs(
        '<h2>Today\'s Visiting Chefs</h2>'
        '<p class="no-visiting-chefs">Back soon</p><script></script>',
      );
      expect(quiet.found, isTrue);
    });

    test('the heading alone is not evidence of a quiet day', () {
      for (final html in [
        '<h2><i></i> Today\'s Visiting Chefs</h2><div></div><script></script>',
        '<h2>Today\'s Visiting Chefs</h2>',
      ]) {
        expect(parseTodayChefs(html).found, isFalse, reason: html);
      }
    });

    test('a heading over restructured chef markup is unrecognised', () {
      const renamed = {
        'div': '<div><a href="/x"><p class="h5">RITZ</p></a>'
            '<div class="chef" data-id="26-1"><em>KO-BQ: 11:00 am - 2:00 pm</em>'
            '</div></div>',
        'article': '<article><h3>RITZ</h3><article>KO-BQ</article></article>',
        'table': '<table><tr><td>RITZ</td><td>KO-BQ</td></tr></table>',
        'attribute': '<div><a href="/x"><p class="h5">RITZ</p></a><ul>'
            '<div data-chef="26-1">KO-BQ</div></ul></div>',
        'other attribute': '<a data-chef="26-1"><em>KO-BQ: 11:00 am - 2:00 pm'
            '</em></a>',
      };
      for (final entry in renamed.entries) {
        final parsed = parseTodayChefs(
          '<h2>Today\'s Visiting Chefs</h2>${entry.value}<script></script>',
        );
        expect(parsed.found, isFalse, reason: entry.key);
        expect(parsed.chefs, isEmpty, reason: entry.key);
      }
    });
  });

  group('/dining/visiting-chefs parse', () {
    final schedule = parseChefSchedule(fixture('rit_visiting_chefs.html'));

    test('parses all fourteen days although each is display: none', () {
      expect(schedule.length, 14);
      expect(schedule.keys.first, '2026-10-14');
      expect(schedule.keys.last, '2026-10-27');
    });

    test('chefs by location, with no times', () {
      final day = schedule['2026-10-14']!;
      expect(day['empty'], isFalse);
      final chefs = (day['chefs'] as List).cast<Map<String, dynamic>>();
      expect(chefs.length, 5);
      expect(chefs.first['name'], 'KO-BQ');
      expect(chefs.first['location_name'], 'The Cafe & Market at Crossroads');
      expect(chefs.every((c) => !c.containsKey('start')), isTrue,
          reason: 'this page publishes no times and none are inferred');
      expect(chefs.map((c) => c['name']), contains("D'Mangu"));
    });

    test('p.no-visiting-chefs days are empty days', () {
      expect(schedule['2026-10-17']!['empty'], isTrue);
      expect(schedule['2026-10-17']!['chefs'], isEmpty);
      expect(schedule['2026-10-24']!['empty'], isTrue);
    });

    test('the Meet the Chefs carousel after the last day is ignored', () {
      final last = (schedule['2026-10-27']!['chefs'] as List);
      expect(last.map((c) => (c as Map)['name']), [
        "D'Mangu",
        'P.H. Express',
        "Esan's Kitchen",
        'Tandoor of India',
        'Halal n Out',
      ]);
    });
  });

  group('availability', () {
    test('every menu empty and rit.edu unreadable is unavailable', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: null,
        now: today,
      );
      expect(view['availability'], availabilityUnavailable);
      expect(view['items'], isEmpty);
    });

    test('a rit.edu page with no recognisable structure is unavailable', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(
          menusHtml: '<html>nothing here</html>',
          scheduleHtml: '<html>nor here</html>',
        ),
        now: today,
      );
      expect(view['availability'], availabilityUnavailable);
    });

    test('rit.edu data from another day cannot answer for today', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(
          menusHtml: fixture('rit_dining_menus.html'),
          date: '2026-10-13',
        ),
        now: today,
      );
      expect(view['availability'], availabilityUnavailable);
    });

    test('no snapshots at all is unavailable', () {
      final view =
          visitingChefsView(tigerCenter: null, rit: null, now: today);
      expect(view['availability'], availabilityUnavailable);
    });

    test('a valid rit.edu page with no chefs is a real empty day', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(
          menusHtml: emptyMenusHtml,
        ),
        now: today,
      );
      expect(view['availability'], availabilityEmpty);
    });

    test('a p.no-visiting-chefs day is empty and names the next chef', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(scheduleHtml: fixture('rit_visiting_chefs.html')),
        now: DateTime.utc(2026, 10, 17, 16),
      );
      expect(view['availability'], availabilityEmpty);
      final next = view['next'] as Map<String, dynamic>;
      expect(next['date'], '2026-10-18');
      expect(next['name'], isNotEmpty);
      expect(next['location_name'], isNotEmpty);
    });

    test('next skips empty days and is null when nothing is upcoming', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(scheduleHtml: fixture('rit_visiting_chefs.html')),
        now: DateTime.utc(2026, 10, 24, 16),
      );
      expect((view['next'] as Map)['date'], '2026-10-25');

      final none = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: {
          'service_date': '2026-10-14',
          'today': null,
          'today_ok': true,
          'schedule_ok': true,
          'schedule': {
            '2026-10-14': {
              'empty': true,
              'unknown': false,
              'chefs': <dynamic>[],
            },
          },
        },
        now: today,
      );
      expect(none['availability'], availabilityEmpty);
      expect(none['next'], isNull);
    });

    test('a snapshot in the old format cannot confirm an empty day', () {
      // What cc11c39 stored: no today_ok, schedule_ok or unknown, and an
      // unparsed day marked empty.
      final old = {
        'service_date': '2026-10-14',
        'today': {'date': '2026-10-14', 'found': true, 'chefs': <dynamic>[]},
        'schedule': {
          '2026-10-14': {'empty': true, 'chefs': <dynamic>[]},
        },
      };
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: old,
        now: today,
      );
      expect(view['availability'], availabilityUnavailable);

      // Its chefs still show, though.
      final withChefs = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: {
          ...old,
          'today': {
            'date': '2026-10-14',
            'found': true,
            'chefs': parseTodayChefs(fixture('rit_dining_menus.html')).chefs,
          },
        },
        now: today,
      );
      expect(withChefs['availability'], availabilityAvailable);
    });

    test('TigerCenter publishing menus but no chef is a real empty day', () {
      final tc = tigerCenter();
      (tc['locations'] as List).first['menus'] = [
        {'id': 1, 'name': 'Soup', 'category': 'Soup'},
      ];
      final view = visitingChefsView(tigerCenter: tc, rit: null, now: today);
      expect(view['availability'], availabilityEmpty);
    });

    test('today\'s chefs come from /menus with times on the campus clock', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(
          menusHtml: fixture('rit_dining_menus.html'),
          scheduleHtml: fixture('rit_visiting_chefs.html'),
        ),
        now: today,
      );
      expect(view['availability'], availabilityAvailable);
      final items = (view['items'] as List).cast<Map<String, dynamic>>();
      expect(items.length, 5);
      expect(items.first['start_time'], '2026-10-14T11:00:00-04:00');
      expect(items.first['end_time'], '2026-10-14T14:00:00-04:00');
      expect(items.first['cuisine'], 'Korean fusion cuisine');
      expect(items.map((i) => i['id']).toSet().length, 5);
    });

    test('the schedule fills in when /menus is missing, without times', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(scheduleHtml: fixture('rit_visiting_chefs.html')),
        now: today,
      );
      expect(view['availability'], availabilityAvailable);
      final items = (view['items'] as List).cast<Map<String, dynamic>>();
      expect(items.length, 5);
      expect(items.every((i) => i['start_time'] == null), isTrue);
      // Matched to TigerCenter by name alone.
      expect(items.first['location_id'], 23);
    });

    test('TigerCenter chefs are used and not duplicated if it recovers', () {
      final view = visitingChefsView(
        tigerCenter: tigerCenter(withChef: true),
        rit: ritSnapshot(menusHtml: fixture('rit_dining_menus.html')),
        now: today,
      );
      final items = (view['items'] as List).cast<Map<String, dynamic>>();
      expect(items.length, 6);
      expect(items.last['name'], 'Chef Ana');
      expect(items.last['location_id'], 21);
    });
  });

  group('review blockers', () {
    test('yesterday\'s TigerCenter chef is not today\'s (day rollover)', () {
      final yesterday = tigerCenter(withChef: true)
        ..['service_date'] = '2026-10-13';
      final view = visitingChefsView(
        tigerCenter: yesterday,
        rit: null,
        now: today,
      );
      expect(view['items'], isEmpty);
      expect(view['availability'], availabilityUnavailable,
          reason: 'a day old payload cannot confirm today either');

      final sameDay = visitingChefsView(
        tigerCenter: tigerCenter(withChef: true),
        rit: null,
        now: today,
      );
      expect((sameDay['items'] as List).length, 1);
    });

    test('cached chefs still show when both reads failed, but empty does not',
        () {
      final cachedChefs = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(
          menusHtml: fixture('rit_dining_menus.html'),
          todayOk: false,
          scheduleOk: false,
        ),
        now: today,
      );
      expect(cachedChefs['availability'], availabilityAvailable);

      final cachedEmpty = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: ritSnapshot(
          scheduleHtml: fixture('rit_visiting_chefs.html'),
          menusHtml: emptyMenusHtml,
          todayOk: false,
          scheduleOk: false,
        ),
        now: DateTime.utc(2026, 10, 17, 16),
      );
      expect(cachedEmpty['availability'], availabilityUnavailable);
    });

    test('a day block the parser cannot read is unknown, not empty', () {
      const html = '''
<div class="daily-visiting-chefs" id="day-2026-10-14">
  <h3>Today's Visiting Chefs</h3>
  <section><b>RITZ</b><ol><li>KO-BQ</li></ol></section>
</div>
<div class="daily-visiting-chefs" id="day-2026-10-15">
  <h3>Visiting Chefs for Thu, Oct 15</h3>
  <p class="no-visiting-chefs">Come visit again</p>
</div>''';
      final days = parseChefSchedule(html);
      expect(days['2026-10-14']!['unknown'], isTrue);
      expect(days['2026-10-14']!['empty'], isFalse);
      expect(days['2026-10-15']!['empty'], isTrue);
      expect(days['2026-10-15']!['unknown'], isFalse);

      final view = visitingChefsView(
        tigerCenter: tigerCenter(),
        rit: {
          'service_date': '2026-10-14',
          'today': null,
          'schedule': days,
        },
        now: today,
      );
      expect(view['availability'], availabilityUnavailable);
    });

    test('chef markup that stops matching under the heading is not found', () {
      final parsed = parseTodayChefs(
        '<h2>Today\'s Visiting Chefs</h2><ul><li><a chefid="x">?</a></li></ul>'
        '<script></script>',
      );
      expect(parsed.found, isFalse);
    });

    test('the live fixture days still read as confirmed empty and chefs', () {
      final days = parseChefSchedule(fixture('rit_visiting_chefs.html'));
      expect(days.values.where((d) => d['unknown'] == true), isEmpty);
    });

    test('last updated is null when no source ever held chefs', () {
      expect(
        chefsLastUpdated(
          tigerCenter: tigerCenter(),
          tigerCenterAt: DateTime.utc(2026, 10, 14, 15),
          rit: null,
          now: today,
        ),
        isNull,
      );
      final stamp = chefsLastUpdated(
        tigerCenter: tigerCenter(),
        tigerCenterAt: null,
        rit: {'today_at': '2026-10-14T11:00:00-04:00'},
        now: today,
      );
      expect(stamp, DateTime.utc(2026, 10, 14, 15));
    });
  });

  group('category match', () {
    final snapshot = <String, dynamic>{
      'service_date': '2026-10-14',
      'locations': [
        {
          'id': 1,
          'name': 'A',
          'menus': [
            {'id': 1, 'name': 'One', 'category': 'Visiting Chef'},
            {'id': 2, 'name': 'Two', 'category': 'visiting chefs'},
            {'id': 3, 'name': 'Three', 'category': 'VISITING CHEF - Dinner'},
            {'id': 4, 'name': 'Four', 'category': 'Soup'},
            {'id': 5, 'name': 'Five', 'category': null},
          ],
        },
      ],
    };

    test('is case insensitive and contains, not exact', () {
      expect(
        menuItemsWithCategory(snapshot, visitingChef).map((i) => i['name']),
        ['One', 'Two', 'Three'],
      );
    });

    test('a null category still returns everything', () {
      expect(menuItemsWithCategory(snapshot, null).length, 5);
    });
  });

  group('envelope', () {
    test('availability defaults to available for old cached bodies', () {
      final c = Collection.fromJson({'data': [], 'stale': false},
          MenuItem.fromJson);
      expect(c.availability, Availability.available);
    });

    test('chef collection carries availability, next and times', () {
      final c = ChefCollection.fromJson({
        'data': [
          {
            'id': 1,
            'name': 'KO-BQ',
            'location_name': 'RITZ',
            'start_time': '2026-10-14T11:00:00-04:00',
            'end_time': '2026-10-14T14:00:00-04:00',
            'cuisine': 'Korean fusion cuisine',
          },
        ],
        'stale': false,
        'availability': 'empty',
        'next': {
          'date': '2026-10-18',
          'name': 'KO-BQ',
          'location_name': 'RITZ',
        },
      });
      expect(c.availability, Availability.empty);
      expect(c.next!.date, DateTime.utc(2026, 10, 18));
      expect(c.data.single.startsAt, isNotNull);
      expect(c.data.single.cuisine, 'Korean fusion cuisine');
    });
  });

  group('LocalBackend', () {
    Directory? temp;
    LocalBackend? backend;
    late Map<String, int> hits;

    LocalBackend build(
      Map<String, http.Response> pages, {
      DateTime Function()? clock,
    }) {
      final dir = temp = Directory.systemTemp.createTempSync('tigerhub-chefs');
      JsonStore.overrideForTesting(dir);
      hits = {};
      return LocalBackend(
        upstream: Upstream(
          client: MockClient((request) async {
            final key = request.url.origin + request.url.path;
            hits[key] = (hits[key] ?? 0) + 1;
            return pages[key] ?? http.Response('not found', 404);
          }),
          maxRetries: 1,
        ),
        store: JsonStore.overrideForTestingInstance,
        clock: clock,
      );
    }

    final tcUrl = tigerCenterUrl;

    setUp(() => RitClock.pin(today));

    tearDown(() {
      RitClock.reset();
      backend?.close();
      backend = null;
      if (temp?.existsSync() ?? false) temp!.deleteSync(recursive: true);
    });

    test('registered at a thirty minute interval', () {
      expect(LocalBackend.sources[ritChefsSource]!.cadence,
          const Duration(minutes: 30));
    });

    test('serves chefs from rit.edu and reads from cache the second time',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      backend = build({
        tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
        ritMenusUrl: http.Response(fixture('rit_dining_menus.html'), 200),
        ritVisitingChefsUrl:
            http.Response(fixture('rit_visiting_chefs.html'), 200),
      });

      final first = await backend!.fetch('/dining/visiting-chefs');
      expect(first['availability'], availabilityAvailable);
      expect((first['data'] as List).length, 5);
      expect(hits[ritMenusUrl], 1);
      expect(hits[ritVisitingChefsUrl], 1);

      // Well inside thirty minutes, so no second request to rit.edu however
      // many times the screen asks.
      await backend!.fetch('/dining/visiting-chefs');
      await backend!.fetch('/dining/visiting-chefs');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hits[ritMenusUrl], 1);
      expect(hits[ritVisitingChefsUrl], 1);
    });

    Map<String, http.Response> livePages({String? menus}) => {
      tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
      ritMenusUrl: http.Response(menus ?? fixture('rit_dining_menus.html'), 200),
      ritVisitingChefsUrl:
          http.Response(fixture('rit_visiting_chefs.html'), 200),
    };

    test('pull to refresh keeps rit.edu to thirty minutes, then refetches',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var now = DateTime.utc(2026, 10, 14, 16);
      final start = now;
      backend = build(livePages(), clock: () => now);

      await backend!.fetch('/dining/visiting-chefs');
      expect(hits[ritMenusUrl], 1);
      expect(hits[tcUrl], 1);

      // Pulling again and again inside half an hour, past the global one
      // minute floor, still never reaches rit.edu.
      for (final minutes in [0, 2, 5, 12, 29]) {
        now = start.add(Duration(minutes: minutes));
        await backend!.refreshNow();
      }
      expect(hits[ritMenusUrl], 1, reason: 'inside thirty minutes');
      expect(hits[ritVisitingChefsUrl], 1);
      expect(hits[tcUrl], greaterThan(1),
          reason: 'other sources keep the one minute floor');

      now = start.add(const Duration(minutes: 31));
      await backend!.refreshNow();
      expect(hits[ritMenusUrl], 2, reason: 'a pull after thirty minutes');
      expect(hits[ritVisitingChefsUrl], 2);

      // And an ordinary read does not refetch inside the next thirty.
      now = start.add(const Duration(minutes: 40));
      await backend!.fetch('/dining/visiting-chefs');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hits[ritMenusUrl], 2);
    });

    test('a failed refresh cannot confirm a quiet day, and is retried soon',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Saturday 10-17 is a day the schedule marks as having no chefs.
      RitClock.pin(DateTime.utc(2026, 10, 17, 16));
      var now = DateTime.utc(2026, 10, 17, 16);
      final start = now;
      final pages = livePages(
        menus: emptyMenusHtml,
      );
      backend = build(pages, clock: () => now);

      final quiet = await backend!.fetch('/dining/visiting-chefs');
      expect(quiet['availability'], availabilityEmpty);

      // Both rit.edu pages go down. The cached empty day must not be repeated
      // as an answer.
      pages.remove(ritMenusUrl);
      pages.remove(ritVisitingChefsUrl);
      now = start.add(const Duration(minutes: 31));
      await backend!.refreshNow();
      final down = await backend!.fetch('/dining/visiting-chefs');
      expect(down['availability'], availabilityUnavailable);

      // A failed snapshot is retried after five minutes, not another thirty.
      pages.addAll(livePages(
        menus: emptyMenusHtml,
      ));
      final before = hits[ritMenusUrl]!;
      // Repeated pulls and reads inside five minutes of the failure never
      // reach rit.edu, not even at the global one minute floor.
      for (final minutes in [32, 33, 34, 35]) {
        now = start.add(Duration(minutes: minutes));
        await backend!.refreshNow();
        await backend!.fetch('/dining/visiting-chefs');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hits[ritMenusUrl], before,
          reason: 'inside five minutes of a failed attempt');

      now = start.add(const Duration(minutes: 36, seconds: 1));
      await backend!.refreshNow();
      expect(hits[ritMenusUrl], before + 1,
          reason: 'one request once the five minutes are up');
      final back = await backend!.fetch('/dining/visiting-chefs');
      expect(back['availability'], availabilityEmpty);
    });

    test('a snapshot stored before the ok fields existed is refetched sooner',
        () {
      expect(ritChefsFailed({'service_date': '2026-10-14'}), isTrue);
      expect(
        ritChefsFailed({'today_ok': true, 'schedule_ok': true}),
        isFalse,
      );
      expect(
        ritChefsFailed({'today_ok': true, 'schedule_ok': false}),
        isTrue,
      );
    });

    test('a 200 with unrecognisable pages is a failed attempt, not an update',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var now = DateTime.utc(2026, 10, 14, 16);
      final start = now;
      const garbage = '<html><body>Redesigned</body></html>';
      final pages = {
        tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
        ritMenusUrl: http.Response(garbage, 200),
        ritVisitingChefsUrl: http.Response(garbage, 200),
      };
      backend = build(pages, clock: () => now);

      final first = await backend!.fetch('/dining/visiting-chefs');
      expect(first['availability'], availabilityUnavailable);
      expect(first['last_updated'], isNull);
      expect(hits[ritMenusUrl], 1);

      // Not a hammer: nothing more inside five minutes, however often asked.
      for (final minutes in [0, 1, 2, 4]) {
        now = start.add(Duration(minutes: minutes));
        await backend!.refreshNow();
        await backend!.fetch('/dining/visiting-chefs');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hits[ritMenusUrl], 1);

      // Not a lockout: five minutes on it is tried again, and when the site
      // is readable again it recovers, with a real time.
      pages[ritMenusUrl] = http.Response(fixture('rit_dining_menus.html'), 200);
      pages[ritVisitingChefsUrl] =
          http.Response(fixture('rit_visiting_chefs.html'), 200);
      now = start.add(const Duration(minutes: 5, seconds: 1));
      await backend!.refreshNow();
      expect(hits[ritMenusUrl], 2);
      final back = await backend!.fetch('/dining/visiting-chefs');
      expect(back['availability'], availabilityAvailable);
      expect(back['last_updated'], isNotNull);
    });

    test('a first run outage has no last updated time', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      backend = build({
        tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
      });
      final chefs = await backend!.fetch('/dining/visiting-chefs');
      expect(chefs['availability'], availabilityUnavailable);
      expect(chefs['last_updated'], isNull);
    });

    test('both sources down is unavailable, not empty', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      backend = build({
        tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
      });

      final chefs = await backend!.fetch('/dining/visiting-chefs');
      expect(chefs['availability'], availabilityUnavailable);
      expect(chefs['data'], isEmpty);
    });

    test('specials report unavailable when every menu is empty', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      backend = build({
        tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
      });

      final specials = await backend!.fetch('/dining/specials');
      expect(specials['availability'], availabilityUnavailable);
      expect(specials['data'], isEmpty);
    });

    test('a working rit.edu with a quiet day is empty with the next chef',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      RitClock.pin(DateTime.utc(2026, 10, 17, 16));
      backend = build({
        tcUrl: http.Response(fixture('tc_dining_all_empty_menus.json'), 200),
        ritMenusUrl: http.Response(
          emptyMenusHtml,
          200,
        ),
        ritVisitingChefsUrl:
            http.Response(fixture('rit_visiting_chefs.html'), 200),
      });

      final chefs = await backend!.fetch('/dining/visiting-chefs');
      expect(chefs['availability'], availabilityEmpty);
      expect((chefs['next'] as Map)['date'], '2026-10-18');
    });
  });
}
