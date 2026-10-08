/// Hotel and campus Wi-Fi captive portals answer every request with a 200 and
/// an HTML sign-in page. None of that may be read as data, and none of it may
/// replace a good snapshot.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/sources/athletics.dart';
import 'package:tigerhub/data/sources/campusgroups.dart';
import 'package:tigerhub/data/sources/maps_occupancy.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/data/upstream.dart';

const _portal = '<!DOCTYPE html><html><head><title>Sign in to Wi-Fi</title>'
    '</head><body><form action="/login"><input name="user"></form></body></html>';

Upstream _portalClient() => Upstream(
  client: MockClient(
    (_) async => http.Response(
      _portal,
      200,
      headers: {'content-type': 'text/html'},
    ),
  ),
  maxRetries: 1,
);

void main() {
  group('a portal page is never data', () {
    test('athletics iCal throws, so the old snapshot stays', () {
      expect(scrapeAthletics(_portalClient()), throwsA(isA<UpstreamError>()));
    });

    test('CampusGroups iCal throws, so the old snapshot stays', () {
      expect(
        scrapeCampusGroups(_portalClient()),
        throwsA(isA<UpstreamError>()),
      );
    });

    test('recreation hours HTML throws, so the old snapshot stays', () {
      expect(scrapeRecreation(_portalClient()), throwsA(isA<UpstreamError>()));
    });

    test('JSON endpoints throw on HTML', () {
      expect(
        _portalClient().getJson('https://example.test/x'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('occupancy: no answer is not "no sensor"', () {
    test('a portal page is unanswered', () async {
      final probe = await probeOccupancy(_portalClient(), 7);
      expect(probe.answered, isFalse);
      expect(probe.reading, isNull);
    });

    test('an error status is unanswered', () async {
      final client = Upstream(
        client: MockClient((_) async => http.Response('nope', 500)),
        maxRetries: 1,
      );
      expect((await probeOccupancy(client, 7)).answered, isFalse);
    });

    test('a valid payload with no density is a real "no sensor"', () async {
      final client = Upstream(
        client: MockClient(
          (_) async => http.Response('[{"_1":2},"routes/x",3]\n', 200),
        ),
        maxRetries: 1,
      );
      final probe = await probeOccupancy(client, 7);
      expect(probe.answered, isTrue);
      expect(probe.reading, isNull);
    });

    test('looksLikeTurboStream rejects HTML and accepts the payload', () {
      expect(looksLikeTurboStream(_portal), isFalse);
      expect(looksLikeTurboStream(''), isFalse);
      expect(looksLikeTurboStream('[1,2]\n'), isTrue);
    });
  });

  group('a corrupted snapshot is a miss, not a crash', () {
    late Directory dir;
    late JsonStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tigerhub_store_');
      store = JsonStore.overrideForTesting(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('truncated JSON reads as null and can be overwritten', () async {
      File('${dir.path}/${JsonStore.fileNameFor('dining')}')
          .writeAsStringSync('{"fetched_at": "2026-10-08T00:00:00Z", "bod');
      expect(await store.read('dining'), isNull);
      expect(await store.fingerprintOf('dining'), isNull);

      await store.write('dining', {'locations': <dynamic>[]});
      expect((await store.read('dining'))?.body, {'locations': <dynamic>[]});
    });

    test('valid JSON of the wrong shape reads as null', () async {
      final file = File('${dir.path}/${JsonStore.fileNameFor('events')}');
      file.writeAsStringSync(jsonEncode([1, 2, 3]));
      expect(await store.read('events'), isNull);
      file.writeAsStringSync(jsonEncode({'body': 'not a map'}));
      expect(await store.read('events'), isNull);
    });

    test('binary garbage reads as null', () async {
      File('${dir.path}/${JsonStore.fileNameFor('menus')}')
          .writeAsBytesSync([0xff, 0xfe, 0x00, 0x80]);
      expect(await store.read('menus'), isNull);
    });
  });
}
