/// API client.
///
/// Every read follows the same shape: return cached data immediately, then
/// refresh in the background. The three UI states below are deliberately
/// distinct and must not be collapsed into one loading state.
///
/// The name is now slightly historical. There is no API and no server: a
/// [Backend] resolves each path on the device. The shape it returns is the same
/// envelope the server used to send, which is exactly why none of the models or
/// screens below had to change when the server went away.
library;

import 'dart:async';

import '../config.dart';
import '../data/backend.dart';
import '../models/api_models.dart';
import 'cache.dart';

/// How the data in hand should be presented.
enum DataState {
  /// Never had data. First launch only. The one case where a spinner is right.
  priming,

  /// Fresh data from a successful refresh.
  ok,

  /// Have data, it is old. Paint at full opacity with a quiet timestamp.
  /// Never a spinner, never greyed out, never an error.
  stale,

  /// Have data, the last refresh errored. Looks like stale, but the timestamp
  /// carries a subtle warning color.
  failing,
}

/// Data plus how to present it.
class Result<T> {
  const Result({
    required this.value,
    required this.state,
    this.fetchedAt,
    this.error,
  });

  final T? value;
  final DataState state;
  final DateTime? fetchedAt;
  final Object? error;

  bool get hasData => value != null;
  bool get isPriming => state == DataState.priming;
}

class ApiClient {
  ApiClient({Backend? backend, ResponseCache? cache})
    : _backend = backend ?? defaultBackend(),
      _cache = cache ?? ResponseCache.instance;

  /// The local backend, unless a base URL was supplied at build time to compare
  /// against a running server.
  static Backend defaultBackend() => AppConfig.usesRemoteBackend
      ? RemoteBackend(baseUrl: AppConfig.apiBaseUrl)
      : LocalBackend();

  /// Refetch everything, because the user asked.
  ///
  /// Deliberately not on the Backend interface. Only the local backend holds
  /// snapshots and cadences, so it is the only one with anything to
  /// invalidate, and putting it on the interface would make every test fake
  /// carry a no-op that means nothing to it. See `LocalBackend.refreshNow`
  /// for why this is not the same as a tick.
  Future<void> refreshNow() async {
    final backend = _backend;
    if (backend is LocalBackend) await backend.refreshNow();
  }

  /// Query parameters that are derived from the clock rather than chosen, and
  /// so must not appear in a cache key.
  ///
  /// `start` is midnight today. Including it minted a fresh key every day and
  /// never reused or removed yesterday's, so the cache grew by one events
  /// entry of roughly 200 KB per day, forever, in shared_preferences. Android
  /// reads that whole store into memory at launch.
  ///
  /// Dropping it means a launch today can paint yesterday's cached events for
  /// the moment before the refresh lands. That is the offline first contract
  /// working as intended, and the envelope's `last_updated` still says how old
  /// it is.
  static const Set<String> _volatileParams = {'start'};

  static String cacheKeyFor(String path, Map<String, String>? query) {
    if (query == null || query.isEmpty) return path;
    final stable = [
      for (final entry in query.entries)
        if (!_volatileParams.contains(entry.key)) '${entry.key}=${entry.value}',
    ];
    return stable.isEmpty ? path : '$path?${stable.join('&')}';
  }

  final Backend _backend;
  final ResponseCache _cache;

  /// Fetch with cache fallback.
  ///
  /// Emits at most twice: once from cache if present, then once from the
  /// network. A network failure with cached data in hand yields `failing`, not
  /// an error, because a stale cache must never produce an error screen.
  Stream<Result<T>> watch<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, String>? query,
  }) async* {
    final cacheKey = cacheKeyFor(path, query);

    final cached = await _cache.read(cacheKey);
    if (cached != null) {
      yield Result<T>(
        value: parse(cached.body),
        state: DataState.stale,
        fetchedAt: cached.fetchedAt,
      );
    } else {
      yield Result<T>(value: null, state: DataState.priming);
    }

    try {
      final body = await _backend.fetch(path, query);
      await _cache.write(cacheKey, body);

      // The backend reports its own staleness, so the presentation layer
      // mirrors that signal rather than inventing a second one.
      final serverStale = body['stale'] as bool? ?? false;
      yield Result<T>(
        value: parse(body),
        state: serverStale ? DataState.stale : DataState.ok,
        fetchedAt: DateTime.now(),
      );
    } catch (error) {
      if (cached != null) {
        yield Result<T>(
          value: parse(cached.body),
          state: DataState.failing,
          fetchedAt: cached.fetchedAt,
          error: error,
        );
      } else {
        yield Result<T>(value: null, state: DataState.priming, error: error);
      }
    }
  }

  Stream<Result<Collection<DiningLocation>>> dining() =>
      watch('/dining', (j) => Collection.fromJson(j, DiningLocation.fromJson));

  Stream<Result<Collection<CampusEvent>>> events() {
    // From midnight, not from now, so events earlier today are included and
    // can be shown as past rather than silently dropped.
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return watch(
      '/events',
      (j) => Collection.fromJson(j, CampusEvent.fromJson),
      query: {
        'days': '14',
        'limit': '300',
        'start': midnight.toIso8601String(),
      },
    );
  }

  Stream<Result<Collection<MenuItem>>> visitingChefs() => watch(
    '/dining/visiting-chefs',
    (j) => Collection.fromJson(j, MenuItem.fromJson),
  );

  /// Every item RIT has published for today's location menus. TigerCenter
  /// does not use a category named "Special", so this endpoint intentionally
  /// remains unfiltered rather than returning an empty list every day.
  Stream<Result<Collection<MenuItem>>> diningFeatures() => watch(
    '/dining/specials',
    (j) => Collection.fromJson(j, MenuItem.fromJson),
  );

  Stream<Result<Collection<PostOffice>>> postOffices() => watch(
    '/post-offices',
    (j) => Collection.fromJson(j, PostOffice.fromJson),
  );

  /// Today's menu for one location. Only 12 of 24 publish one, so an empty
  /// dish list is a normal answer.
  Stream<Result<MenuDay>> menu(int locationId) =>
      watch('/dining/$locationId/menu', MenuDay.fromJson);

  /// The 24 hour occupancy series for one location. Only the five locations
  /// with a sensor return anything.
  Stream<Result<OccupancyHistory>> occupancyHistory(int locationId) =>
      watch('/dining/$locationId/occupancy', OccupancyHistory.fromJson);

  Stream<Result<Collection<PlaceKind>>> placeKinds() => watch(
    '/campus/places',
    (j) => Collection.fromJson(j, PlaceKind.fromJson),
  );

  Stream<Result<Collection<CampusPlace>>> places(String kind) => watch(
    '/campus/places/$kind',
    (j) => Collection.fromJson(j, CampusPlace.fromJson),
  );

  Stream<Result<Collection<CampusMapFeature>>> campusMap() => watch(
    '/campus/map',
    (j) => Collection.fromJson(j, CampusMapFeature.fromJson),
  );

  Stream<Result<Collection<RecreationFacility>>> recreation() => watch(
    '/recreation/hours',
    (j) => Collection.fromJson(j, RecreationFacility.fromJson),
  );

  Stream<Result<Collection<RoomSummary>>> makerspaceRooms() => watch(
    '/makerspace/rooms',
    (j) => Collection.fromJson(j, RoomSummary.fromJson),
  );

  /// Makerspace hours come from static config, so this endpoint returns a bare
  /// list rather than the usual envelope.
  Stream<Result<List<MakerSpaceHours>>> makerspaceHours() =>
      watchList('/makerspace/hours', MakerSpaceHours.fromJson);

  Stream<Result<Collection<HousingArea>>> housingAreas() => watch(
    '/housing/areas',
    (j) => Collection.fromJson(j, HousingArea.fromJson),
  );

  /// Same cache and staleness behaviour as watch(), for endpoints that return
  /// a bare JSON array instead of the {data, stale} envelope.
  ///
  /// The array is wrapped before caching, because the cache stores objects.
  Stream<Result<List<T>>> watchList<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async* {
    List<T> decode(Map<String, dynamic> body) => [
      for (final item in (body['items'] as List<dynamic>? ?? const []))
        parse(item as Map<String, dynamic>),
    ];

    final cached = await _cache.read(path);
    if (cached != null) {
      yield Result<List<T>>(
        value: decode(cached.body),
        state: DataState.stale,
        fetchedAt: cached.fetchedAt,
      );
    } else {
      yield Result<List<T>>(value: null, state: DataState.priming);
    }

    try {
      final body = await _backend.fetch(path);
      await _cache.write(path, body);
      yield Result<List<T>>(
        value: decode(body),
        state: DataState.ok,
        fetchedAt: DateTime.now(),
      );
    } catch (error) {
      if (cached != null) {
        yield Result<List<T>>(
          value: decode(cached.body),
          state: DataState.failing,
          fetchedAt: cached.fetchedAt,
          error: error,
        );
      } else {
        yield Result<List<T>>(
          value: null,
          state: DataState.priming,
          error: error,
        );
      }
    }
  }

  Stream<Result<MailingAddress>> address(
    String areaId,
    String name,
    String? unit,
  ) => watch(
    '/housing/areas/$areaId/address',
    MailingAddress.fromJson,
    query: {'name': name, if (unit != null && unit.isNotEmpty) 'unit': unit},
  );

  void dispose() => _backend.close();
}
