/// The response cache must not grow without bound.
///
/// It very nearly did. The events cache key embedded midnight-today, so every
/// day minted a fresh key holding roughly 200 KB of events and never reused or
/// removed yesterday's. shared_preferences is read into memory whole at launch,
/// so a month of that is megabytes of dead weight on every start.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('cache keys', () {
    test('a clock derived parameter never reaches the key', () {
      // These are the same request on two different days.
      final monday = ApiClient.cacheKeyFor('/events', {
        'days': '14',
        'limit': '300',
        'start': '2026-08-29T00:00:00.000',
      });
      final tuesday = ApiClient.cacheKeyFor('/events', {
        'days': '14',
        'limit': '300',
        'start': '2026-08-30T00:00:00.000',
      });

      expect(monday, tuesday,
          reason: 'a new key per day is how the cache grew without bound');
      expect(monday, isNot(contains('start')));
      expect(monday, contains('days=14'));
    });

    test('parameters the user actually chose still separate entries', () {
      expect(
        ApiClient.cacheKeyFor('/events', {'days': '14'}),
        isNot(ApiClient.cacheKeyFor('/events', {'days': '30'})),
      );
    });

    test('no query means the bare path', () {
      expect(ApiClient.cacheKeyFor('/dining', null), '/dining');
      expect(ApiClient.cacheKeyFor('/dining', const {}), '/dining');
    });
  });

  group('pruning', () {
    test('drops stale entries and keeps fresh ones', () async {
      final cache = ResponseCache.instance;

      await cache.write('/fresh', {'data': []});
      await cache.write('/stale', {'data': []});

      // Age one entry past the window by rewriting its stamp, through the
      // same store the cache itself uses.
      await SharedPreferencesAsync().setString(
        'cache_at:/stale',
        DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      );

      final removed = await cache.prune(olderThan: const Duration(days: 7));

      expect(removed, 1);
      expect(await cache.read('/stale'), isNull);
      expect(await cache.read('/fresh'), isNotNull,
          reason: 'pruning must not take the data the app is actually using');
    });

    test('is safe to run when there is nothing cached', () async {
      expect(await ResponseCache.instance.prune(), 0);
    });
  });
}
