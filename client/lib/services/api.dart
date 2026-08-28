/// API client.
///
/// Every read follows the same shape: return cached data immediately, then
/// refresh in the background. The three UI states below are deliberately
/// distinct and must not be collapsed into one loading state.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
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
  ApiClient({http.Client? client, ResponseCache? cache})
      : _client = client ?? http.Client(),
        _cache = cache ?? ResponseCache.instance;

  final http.Client _client;
  final ResponseCache _cache;

  static const Duration _timeout = Duration(seconds: 8);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);

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
    final cacheKey = query == null || query.isEmpty
        ? path
        : '$path?${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';

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
      final response =
          await _client.get(_uri(path, query)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', _uri(path, query));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await _cache.write(cacheKey, body);

      // The server reports its own staleness, so the client mirrors that
      // signal rather than inventing a second one.
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

  Stream<Result<Collection<PostOffice>>> postOffices() => watch(
        '/post-offices',
        (j) => Collection.fromJson(j, PostOffice.fromJson),
      );

  Stream<Result<Collection<RoomSummary>>> makerspaceRooms() => watch(
        '/makerspace/rooms',
        (j) => Collection.fromJson(j, RoomSummary.fromJson),
      );

  /// Makerspace hours come from static config, so this endpoint returns a bare
  /// list rather than the usual envelope.
  Stream<Result<List<MakerSpaceHours>>> makerspaceHours() => watchList(
        '/makerspace/hours',
        MakerSpaceHours.fromJson,
      );

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
      final response = await _client.get(_uri(path)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', _uri(path));
      }
      final decoded = jsonDecode(response.body);
      final body = <String, dynamic>{
        'items': decoded is List ? decoded : const [],
      };
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
        yield Result<List<T>>(value: null, state: DataState.priming, error: error);
      }
    }
  }

  Stream<Result<MailingAddress>> address(String areaId, String name, String? unit) =>
      watch(
        '/housing/areas/$areaId/address',
        MailingAddress.fromJson,
        query: {'name': name, if (unit != null && unit.isNotEmpty) 'unit': unit},
      );

  void dispose() => _client.close();
}
