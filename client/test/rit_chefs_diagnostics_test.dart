/// What the chefs scrape records about each rit.edu fetch, and the parser
/// pieces behind it. The report is what a "Menus unavailable" on a phone is
/// read from, on the frame stats screen or a copied report.
library;

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

import 'rit_chefs_formats_test.dart' show menusPage;

List<int> bytesOf(String name) => File('test/fixtures/$name').readAsBytesSync();

final DateTime oct23 = DateTime.utc(2026, 10, 23, 20, 32);

http.Response page(List<int> bytes, [int status = 200]) => http.Response.bytes(
  bytes,
  status,
  headers: {'content-type': 'text/html; charset=UTF-8'},
);

Upstream upstream(Future<http.Response> Function(String url) serve) => Upstream(
  client: MockClient((r) => serve(r.url.origin + r.url.path)),
  maxRetries: 1,
);

void main() {
  setUp(() {
    RitClock.pin(oct23);
    chefsDiagnostics.value = null;
  });
  tearDown(RitClock.reset);

  group('parseTimeRange', () {
    test('the bare side takes the written meridiem unless it would start '
        'after the end', () {
      expect(parseTimeRange('4', '7 p.m.'), (start: '16:00', end: '19:00'));
      expect(parseTimeRange('11', '2 p.m.'), (start: '11:00', end: '14:00'));
      expect(parseTimeRange('12', '2 p.m.'), (start: '12:00', end: '14:00'));
      expect(parseTimeRange('11 a.m.', '2'), (start: '11:00', end: '14:00'));
      expect(parseTimeRange('9', '11 a.m.'), (start: '09:00', end: '11:00'));
      expect(parseTimeRange('11', 'noon'), (start: '11:00', end: '12:00'));
      expect(parseTimeRange('12 am', '1 am'), (start: '00:00', end: '01:00'));
    });

    test('nothing is guessed', () {
      expect(parseTimeRange('11', '2'), isNull);
      expect(parseTimeRange('13 pm', '2 pm'), isNull);
      expect(parseTimeRange('11:75 am', '2 pm'), isNull);
      expect(parseTimeRange('9', '2 a.m.'), isNull);
    });
  });

  test('locationKey ignores case, spacing, punctuation and the alias used', () {
    final ritz = locationKey('RITZ');
    expect(locationKey('ritz sports zone'), ritz);
    expect(locationKey('  RITZ   Sports-Zone. '), ritz);
    expect(locationKey('Brick City Café'), locationKey('Kitchen at Brick City'));
    expect(locationKey('Crossroads'),
        locationKey('The Cafe & Market at Crossroads'));
    expect(locationKey('Global Village Grill'), 'global village grill');
  });

  group('parseTodayChefs counts', () {
    test('skipped and untimed entries are counted, the rest kept', () {
      final parsed = parseTodayChefs(
        menusPage([
          ('RITZ', [
            ('26-1', 'KO-BQ: 11:00 am - 2:00 pm'),
            ('26-2', ''),
            ('26-3', 'P.H. Express: sometime'),
          ]),
        ]),
      );
      expect(parsed.chefs.length, 2);
      expect(parsed.skipped, 1);
      expect(parsed.untimed, 1);
      expect(parsed.reason, isNull);
    });

    test('nothing found says why', () {
      expect(parseTodayChefs('<p>Maintenance</p>').reason, 'no heading');
      expect(
        parseTodayChefs('<h2>Today\'s Visiting Chefs</h2><ul></ul><script>')
            .reason,
        'no chef entries',
      );
      final unreadable = parseTodayChefs(menusPage([
        ('RITZ', [('26-1', '')]),
      ]));
      expect(unreadable.found, isFalse);
      expect(unreadable.skipped, 1);
      expect(unreadable.reason, 'no entry readable');
    });
  });

  group('scrape diagnostics', () {
    final menus = bytesOf('rit_menus_2026-10-23.html');
    final schedule = bytesOf('rit_visiting_chefs_2026-10-23.html');

    test('a good read records status, bytes and what parsed', () async {
      final snapshot = await scrapeRitChefs(
        upstream((url) async => page(url == ritMenusUrl ? menus : schedule)),
      );
      final report = snapshot['diagnostics'] as Map<String, dynamic>;
      expect(report['menus'], {
        'at': '2026-10-23T16:32:00-04:00',
        'status': 200,
        'bytes': menus.length,
        'parsed': 5,
        'skipped': 0,
        'untimed': 0,
        'reason': null,
      });
      expect(report['schedule'], {
        'at': '2026-10-23T16:32:00-04:00',
        'status': 200,
        'bytes': schedule.length,
        'parsed': 5,
        'reason': null,
      });
      expect(chefsDiagnostics.value, report);
    });

    test('an HTTP error and a transport error are recorded by type', () async {
      final snapshot = await scrapeRitChefs(
        upstream((url) async {
          if (url == ritMenusUrl) return page(const [], 503);
          throw http.ClientException('connection reset');
        }),
      );
      final report = snapshot['diagnostics'] as Map<String, dynamic>;
      expect(report['menus'], {
        'at': '2026-10-23T16:32:00-04:00',
        'status': 503,
        'error': 'HTTP',
      });
      expect(report['schedule'], {
        'at': '2026-10-23T16:32:00-04:00',
        'status': null,
        'error': 'ClientException',
      });
      expect(snapshot['today_ok'], isFalse);
    });

    test('a page with no chefs records the reason and stays failed', () async {
      final snapshot = await scrapeRitChefs(
        upstream((url) async => page(
          url == ritMenusUrl ? '<html>Maintenance</html>'.codeUnits : schedule,
        )),
      );
      final menusReport =
          (snapshot['diagnostics'] as Map<String, dynamic>)['menus'] as Map;
      expect(menusReport['parsed'], 0);
      expect(menusReport['reason'], 'no heading');
      expect(snapshot['today_ok'], isFalse);
    });

    test('the text report carries no URL or page content', () async {
      await scrapeRitChefs(
        upstream((url) async {
          if (url == ritMenusUrl) return page(menus);
          throw http.ClientException('failed for $url?token=secret');
        }),
      );
      final lines = chefsDiagnosticsLines(chefsDiagnostics.value);
      expect(lines, [
        'Menus page: HTTP 200, ${menus.length} bytes, 5 chefs, 0 skipped, '
            '0 without a time, at 2026-10-23 16:32',
        'Schedule page: failed, ClientException, at 2026-10-23 16:32',
      ]);
      for (final line in lines) {
        expect(line, isNot(contains('rit.edu')));
        expect(line, isNot(contains('token')));
      }
    });

    test('no report yet says so', () {
      expect(chefsDiagnosticsLines(null), ['No chefs fetch yet']);
    });
  });

  test('a stored report is shown again after a restart', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('tigerhub-diag');
    addTearDown(() => dir.deleteSync(recursive: true));
    final menus = bytesOf('rit_menus_2026-10-23.html');
    final schedule = bytesOf('rit_visiting_chefs_2026-10-23.html');

    LocalBackend start() {
      JsonStore.overrideForTesting(dir);
      return LocalBackend(
        upstream: upstream((url) async {
          if (url == tigerCenterUrl) {
            return http.Response(
              File('test/fixtures/tc_dining_all_empty_menus.json')
                  .readAsStringSync(),
              200,
            );
          }
          return page(url == ritMenusUrl ? menus : schedule);
        }),
        store: JsonStore.overrideForTestingInstance,
      );
    }

    final first = start();
    await first.fetch('/dining/visiting-chefs');
    first.close();
    final stored = chefsDiagnostics.value;
    expect(stored, isNotNull);

    chefsDiagnostics.value = null;
    final second = start();
    await second.fetch('/dining/visiting-chefs');
    second.close();
    expect(chefsDiagnostics.value, stored);
  });
}
