/// Visiting chef times and location names in the formats rit.edu might use.
///
/// On 2026-10-23 Cole read /dining/menus at about 16:10 ET and saw times
/// written "11 a.m.-2 p.m." and "4-7 p.m." under "Brick City Cafe" and "RITZ
/// Sports Zone". Fetches at 16:32 and 21:45 the same day still returned the
/// old "11:00 am - 2:00 pm" format under the old names, saved here as
/// `rit_menus_2026-10-23.html` and `rit_visiting_chefs_2026-10-23.html`. So
/// every new format case below is a synthetic snippet in the page's real
/// markup, and says so in its name.
///
/// These use only what the parser exposed before the change, so the file also
/// runs against the old code.
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

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 16:32 ET on 2026-10-23, when the saved pages were first fetched.
final DateTime oct23 = DateTime.utc(2026, 10, 23, 20, 32);

/// A /dining/menus chef section in the markup the live page uses: a `p.h5`
/// location name, then per chef an anchor with `chefid` and an `<em>` reading
/// "name: times", then the `-chef-holder` popup when [holder] is set.
String menusPage(
  List<(String, List<(String, String)>)> blocks, {
  bool holder = false,
}) {
  final out = StringBuffer(
    '<h2><i class="fa fa-id-badge"></i> Today\'s Visiting Chefs</h2>\n',
  );
  for (final (location, chefs) in blocks) {
    out.writeln('<a href="/dining/location/x" class="link-with-icon see-more">'
        '<p class="h5 mt-4 mb-1">$location</p></a><ul>');
    for (final (id, text) in chefs) {
      out.writeln('<li><a href="/dining/location/x" class="link-with-icon '
          'see-more" onmouseover="displayChefPopup(this)" '
          'onmouseout="hideChefPopup(this)" chefid="$id">\n<em>$text</em></a>');
      if (holder) {
        final name = text.split(':').first;
        out.writeln('<div id="$id-chef-holder" class="pop-up">'
            '<span class="h6 text-dark font-weight-bold">$name</span><br/>'
            '<em class="font-weight-normal small"></em></div>');
      }
      out.writeln('</li>');
    }
    out.writeln('</ul></div>');
  }
  out.writeln('<script></script>');
  return out.toString();
}

Map<String, dynamic> tigerCenterOn(String date) => {
  'service_date': date,
  'locations': parseDining(
    jsonDecode(fixture('tc_dining_all_empty_menus.json'))
        as Map<String, dynamic>,
  ),
};

/// A schedule page whose block for [date] lists [chefs] as (location, name).
String schedulePage(String date, List<(String, String)> chefs) {
  final out = StringBuffer(
    '<div class="daily-visiting-chefs" id="day-$date" style="display: none;">'
    '<h3>Today\'s Visiting Chefs</h3>',
  );
  for (final (location, name) in chefs) {
    out.write('<div><span>$location</span><ul class="mt-2">'
        '<li><em>$name</em></li></ul></div>');
  }
  out.write('</div>');
  return out.toString();
}

void main() {
  group('time formats', () {
    void expectTimes(String text, String name, String start, String end) {
      final split = splitChefText(text);
      expect(split.name, name, reason: text);
      expect(split.start, start, reason: text);
      expect(split.end, end, reason: text);
    }

    test('synthetic: 11 a.m.-2 p.m.', () {
      expectTimes("Esan's Kitchen: 11 a.m.-2 p.m.", "Esan's Kitchen",
          '11:00', '14:00');
    });

    test('synthetic: 11am-2pm', () {
      expectTimes('KO-BQ: 11am-2pm', 'KO-BQ', '11:00', '14:00');
    });

    test('synthetic: 11:00 am - 2:00 pm and 11:00 AM - 2:00 PM', () {
      expectTimes('KO-BQ: 11:00 am - 2:00 pm', 'KO-BQ', '11:00', '14:00');
      expectTimes('KO-BQ: 11:00 AM - 2:00 PM', 'KO-BQ', '11:00', '14:00');
    });

    test('synthetic: an en dash between the times', () {
      expectTimes('KO-BQ: 11 a.m.–2 p.m.', 'KO-BQ', '11:00', '14:00');
    });

    test('synthetic: "to" between the times', () {
      expectTimes('KO-BQ: 11:30a.m. to 2 p.m.', 'KO-BQ', '11:30', '14:00');
    });

    test('synthetic: 4-7 p.m. writes p.m. once', () {
      expectTimes('P.H. Express: 4-7 p.m.', 'P.H. Express', '16:00', '19:00');
      expectTimes('P.H. Express: 4 to 7 pm', 'P.H. Express', '16:00', '19:00');
    });

    test('synthetic: 11-2 p.m. starts in the morning', () {
      expectTimes('D\'Mangu: 11-2 p.m.', "D'Mangu", '11:00', '14:00');
      expectTimes('D\'Mangu: 11-12 p.m.', "D'Mangu", '11:00', '12:00');
    });

    test('synthetic: noon', () {
      expectTimes('KO-BQ: 11 a.m.-noon', 'KO-BQ', '11:00', '12:00');
    });

    test('synthetic: an unreadable time keeps the chef without a time', () {
      final split = splitChefText("Esan's Kitchen: 11 a.m.-2 q.m.");
      expect(split.name, "Esan's Kitchen");
      expect(split.start, isNull);
      expect(split.end, isNull);

      // No meridiem anywhere is ambiguous, so it is not guessed.
      final bare = splitChefText('KO-BQ: 11-2');
      expect(bare.name, 'KO-BQ');
      expect(bare.start, isNull);
    });
  });

  group('/dining/menus', () {
    test('live 2026-10-23 page parses to its five chefs', () {
      final parsed = parseTodayChefs(fixture('rit_menus_2026-10-23.html'));
      expect(parsed.found, isTrue);
      expect(
        [
          for (final c in parsed.chefs)
            '${c['location_name']} | ${c['name']} | ${c['start']}-${c['end']}',
        ],
        [
          "The Cafe & Market at Crossroads | D'Mangu | 11:00-14:00",
          "Gracie's | D'Mangu | 16:00-19:00",
          "Kitchen at Brick City | California Rollin' | 11:00-14:00",
          'RITZ | KO-BQ | 11:00-14:00',
          'RITZ | P.H. Express | 16:00-19:00',
        ],
      );
    });

    test("synthetic: Cole's 16:10 list in the new format parses to exactly "
        'its five chefs', () {
      final parsed = parseTodayChefs(
        menusPage([
          ('Crossroads', [
            ('23-1', "Esan&#039;s Kitchen: 11 a.m.-2 p.m."),
            ('23-2', 'P.H. Express: 4-7 p.m.'),
          ]),
          ('Brick City Cafe', [('22-1', 'Tandoor of India: 11 a.m.-2 p.m.')]),
          ('RITZ Sports Zone', [
            ('26-1', "D&#039;Mangu: 4-7 p.m."),
            ('26-2', "just chik&#039;n: 11 a.m.-2 p.m."),
          ]),
        ], holder: true),
      );
      expect(parsed.found, isTrue);
      expect(
        [
          for (final c in parsed.chefs)
            '${c['location_id']} ${c['location_name']} | ${c['name']} | '
                '${c['start']}-${c['end']}',
        ],
        [
          "23 Crossroads | Esan's Kitchen | 11:00-14:00",
          '23 Crossroads | P.H. Express | 16:00-19:00',
          '22 Brick City Cafe | Tandoor of India | 11:00-14:00',
          "26 RITZ Sports Zone | D'Mangu | 16:00-19:00",
          "26 RITZ Sports Zone | just chik'n | 11:00-14:00",
        ],
      );
    });

    test('synthetic: a chefid too long to be a number loses nothing else', () {
      final parsed = parseTodayChefs(
        menusPage([
          ('RITZ', [
            ('26-1', 'KO-BQ: 11:00 am - 2:00 pm'),
            ('99999999999999999999-1', 'Mystery: 11:00 am - 2:00 pm'),
            ('26-2', 'P.H. Express: 4:00 pm - 7:00 pm'),
          ]),
        ]),
      );
      expect(parsed.chefs.map((c) => c['name']),
          containsAll(['KO-BQ', 'P.H. Express']));
    });

    test('synthetic: a chefid that is not a location id still lists the chef',
        () {
      final parsed = parseTodayChefs(
        menusPage([
          ('RITZ Sports Zone', [('ritz-1', 'KO-BQ: 11 a.m.-2 p.m.')]),
        ]),
      );
      expect(parsed.found, isTrue);
      expect(parsed.chefs.single['name'], 'KO-BQ');
      expect(parsed.chefs.single['location_name'], 'RITZ Sports Zone');

      // The projection finds the location by name instead.
      final view = visitingChefsView(
        tigerCenter: tigerCenterOn('2026-10-23'),
        rit: {
          'today': {
            'date': '2026-10-23',
            'found': true,
            'chefs': parsed.chefs,
          },
        },
        now: oct23,
      );
      final item = (view['items'] as List).single as Map<String, dynamic>;
      expect(item['location_id'], 26);
      expect(item['location_name'], 'RITZ Sports Zone');
    });

    test('synthetic: one entry with no name is dropped and the rest kept', () {
      final parsed = parseTodayChefs(
        menusPage([
          ('RITZ', [
            ('26-1', 'KO-BQ: 11:00 am - 2:00 pm'),
            ('26-2', ''),
            ('26-3', 'P.H. Express: 4:00 pm - 7:00 pm'),
          ]),
        ]),
      );
      expect(parsed.chefs.map((c) => c['name']), ['KO-BQ', 'P.H. Express']);
    });
  });

  group('location names', () {
    Map<String, dynamic> scheduleOnly(List<(String, String)> chefs) =>
        visitingChefsView(
          tigerCenter: tigerCenterOn('2026-10-23'),
          rit: {
            'service_date': '2026-10-23',
            'today': null,
            'schedule': parseChefSchedule(schedulePage('2026-10-23', chefs)),
          },
          now: oct23,
        );

    Map<String, Object?> where(Map<String, dynamic> view) => {
      for (final i in (view['items'] as List).cast<Map<String, dynamic>>())
        i['name'] as String: i['location_id'],
    };

    test('old names find their TigerCenter location', () {
      final view = scheduleOnly([
        ('Kitchen at Brick City', 'Tandoor of India'),
        ('RITZ', "D'Mangu"),
        ('The Cafe &amp; Market at Crossroads', 'P.H. Express'),
      ]);
      expect(where(view), {
        'Tandoor of India': 22,
        "D'Mangu": 26,
        'P.H. Express': 23,
      });
    });

    test('synthetic: new names find the same locations', () {
      final view = scheduleOnly([
        ('Brick City Cafe', 'Tandoor of India'),
        ('RITZ Sports Zone', "D'Mangu"),
        ('Crossroads', 'P.H. Express'),
        ('brick  city  CAFÉ', 'Esan&#039;s Kitchen'),
      ]);
      expect(where(view), {
        'Tandoor of India': 22,
        "D'Mangu": 26,
        'P.H. Express': 23,
        "Esan's Kitchen": 22,
      });
      // The card still says what RIT said.
      expect(
        (view['items'] as List).map((i) => (i as Map)['location_name']),
        contains('RITZ Sports Zone'),
      );
    });

    test('synthetic: an unknown location still shows the chef under its name',
        () {
      final view = scheduleOnly([('Global Village Grill', 'KO-BQ')]);
      expect(view['availability'], availabilityAvailable);
      final item = (view['items'] as List).single as Map<String, dynamic>;
      expect(item['name'], 'KO-BQ');
      expect(item['location_name'], 'Global Village Grill');
      expect(item['location_id'], isNull);
    });
  });

  group('LocalBackend', () {
    Directory? temp;
    LocalBackend? backend;

    setUp(() => RitClock.pin(oct23));

    tearDown(() {
      RitClock.reset();
      backend?.close();
      backend = null;
      if (temp?.existsSync() ?? false) temp!.deleteSync(recursive: true);
    });

    /// rit.edu's pages as it serves them: UTF-8 bytes with a charset header.
    http.Response page(List<int> bytes) => http.Response.bytes(
      bytes,
      200,
      headers: {'content-type': 'text/html; charset=UTF-8'},
    );

    LocalBackend build(List<int> menus, List<int> schedule) {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = temp = Directory.systemTemp.createTempSync('tigerhub-chefs');
      JsonStore.overrideForTesting(dir);
      final pages = {
        tigerCenterUrl: http.Response(
          fixture('tc_dining_all_empty_menus.json'),
          200,
        ),
        ritMenusUrl: page(menus),
        ritVisitingChefsUrl: page(schedule),
      };
      return LocalBackend(
        upstream: Upstream(
          client: MockClient(
            (r) async =>
                pages[r.url.origin + r.url.path] ??
                http.Response('not found', 404),
          ),
          maxRetries: 1,
        ),
        store: JsonStore.overrideForTestingInstance,
      );
    }

    List<int> bytesOf(String name) =>
        File('test/fixtures/$name').readAsBytesSync();

    test('the live 2026-10-23 pages give five chefs', () async {
      backend = build(
        bytesOf('rit_menus_2026-10-23.html'),
        bytesOf('rit_visiting_chefs_2026-10-23.html'),
      );
      final chefs = await backend!.fetch('/dining/visiting-chefs');
      expect(chefs['availability'], availabilityAvailable);
      expect((chefs['data'] as List).length, 5);
    });

    test('synthetic: one bad UTF-8 byte in a chef name costs only that byte',
        () async {
      final menus = bytesOf('rit_menus_2026-10-23.html');
      // 0xFF is never valid UTF-8. Put it inside the first chef's name.
      final at = latin1.decode(menus).indexOf('KO-BQ:');
      final broken = [...menus]..[at + 2] = 0xFF;
      backend = build(broken, bytesOf('rit_visiting_chefs_2026-10-23.html'));

      final chefs = await backend!.fetch('/dining/visiting-chefs');
      expect(chefs['availability'], availabilityAvailable);
      final names = [
        for (final c in (chefs['data'] as List)) (c as Map)['name'],
      ];
      expect(names.length, 5);
      expect(names, contains('P.H. Express'));
      expect(names, contains('KO-BQ'), reason: 'the popup span still names it');
    });
  });
}
