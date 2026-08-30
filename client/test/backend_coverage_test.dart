/// Every path the app asks for must be served locally.
///
/// There is no server to fall back on any more. A path that `ApiClient`
/// requests but `LocalBackend` does not route would not fail loudly, it would
/// surface as a permanently failing card in the UI, which looks exactly like a
/// network problem. So the routing table is checked against the real list.
///
/// The list below is every path literal in `services/api.dart`. If a screen
/// starts asking for something new, add it here and route it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:tigerhub/data/local_backend.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/upstream.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LocalBackend backend;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tigerhub-coverage');
    JsonStore.overrideForTesting(temp);
    backend = LocalBackend(
      // Offline on purpose. Routing is what is under test, not scraping, and
      // an unrouted path must be distinguishable from an unreachable upstream.
      upstream: Upstream(
        client: MockClient((_) async => throw const SocketException('offline')),
        maxRetries: 1,
      ),
      store: JsonStore.overrideForTestingInstance,
    );
  });

  tearDown(() {
    backend.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  const paths = [
    '/dining',
    '/dining/visiting-chefs',
    '/dining/specials',
    '/dining/23/menu',
    '/dining/23/occupancy',
    '/dining/21/menu',
    '/events',
    '/events/organizers',
    '/post-offices',
    '/campus/places',
    '/campus/places/water',
    '/recreation/hours',
    '/makerspace/equipment',
    '/makerspace/rooms',
    '/makerspace/hours',
    '/housing/areas',
    '/housing/areas/residence-halls/address',
  ];

  for (final path in paths) {
    test('$path is routed to a local source', () async {
      try {
        await backend.fetch(path);
      } on UpstreamError catch (error) {
        // Any other failure is fine here: offline, no sensor, no snapshot yet.
        // Only "nothing serves this" is a routing bug.
        expect(
          error.message,
          isNot(contains('no local source serves')),
          reason: '$path has no route in LocalBackend',
        );
      } catch (_) {
        // Offline, as expected.
      }
    });
  }

  test('an unknown path still reports that it is unrouted', () async {
    // The guard above is only meaningful if this is the message it looks for.
    await expectLater(
      backend.fetch('/not/a/real/path'),
      throwsA(
        isA<UpstreamError>().having(
          (e) => e.message,
          'message',
          contains('no local source serves'),
        ),
      ),
    );
  });

  test('the static config endpoints answer with no network at all', () async {
    // These are bundled assets, so they must work on a first launch that has
    // never once reached the internet. Mail is the thing people look up when
    // they are standing at a counter with no signal.
    final offices = await backend.fetch('/post-offices');
    expect((offices['data'] as List).length, greaterThanOrEqualTo(2));

    final areas = await backend.fetch('/housing/areas');
    expect((areas['data'] as List).length, greaterThanOrEqualTo(6));

    final address = await backend.fetch(
      '/housing/areas/residence-halls/address',
      {'name': 'Cole', 'unit': 'Peterson 1234'},
    );
    expect(address['lines'], [
      'Cole',
      'Peterson 1234',
      '43 Greenleaf Court',
      'Rochester NY 14623',
    ]);
    expect(address['direct_delivery'], isNot(true));
  });

  test('a direct delivery area bypasses the campus post offices', () async {
    // RIT Inn and 175 Jefferson get mail at the property, and 1 Lomb Memorial
    // Drive is explicitly not a student package address (CLAUDE.md 7.9).
    final address = await backend.fetch(
      '/housing/areas/rit-inn/address',
      {'name': 'Cole'},
    );
    expect(address['direct_delivery'], isTrue);
    expect(address['lines'], [
      'Cole',
      '5257 W Henrietta Rd',
      'Henrietta NY 14467',
    ]);
  });
}
