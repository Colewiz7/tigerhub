/// Scrapes RIT from the device.
///
/// This replaces the FastAPI server. The app no longer depends on a homelab
/// being up, which is the whole reason it exists.
///
/// Two obligations moved here along with the scraping, and both matter more on
/// a device than they did on one server, because there is now one of these per
/// install rather than one in total:
///
///  1. **Cadence.** CLAUDE.md 6 says scheduled scrapes only, never per request.
///     A source is refreshed only when its snapshot is older than its cadence,
///     so opening a tab five times does not scrape five times. Every read is
///     served from the stored snapshot either way.
///  2. **Identification.** Every outbound call goes through `upstream.dart`,
///     which is the only place that sets the User-Agent.
///
/// Reads never block on a scrape when a snapshot exists: the stored copy is
/// returned immediately and the refresh runs behind it. That is what keeps the
/// offline first requirement (CLAUDE.md 3.1) true now that "offline" also means
/// "the upstream is slow".
library;

import 'dart:async';

import 'backend.dart';
import 'campus_time.dart';
import 'sources/athletics.dart';
import 'sources/campusgroups.dart';
import 'sources/drupal_events.dart';
import 'sources/tigercenter.dart';
import 'static_config.dart';
import 'store.dart';
import 'upstream.dart';

/// One scraped upstream, with the cadence it is polled at.
///
/// The intervals are the backend's, unchanged: dining hourly, events every few
/// hours, makerspace every fifteen minutes (CLAUDE.md 6).
class SourceSpec {
  const SourceSpec({
    required this.name,
    required this.cadence,
    required this.scrape,
  });

  final String name;
  final Duration cadence;
  final Future<Map<String, dynamic>> Function(Upstream) scrape;
}

/// How long past its cadence a source's data counts as stale, mirroring
/// `backend/app/freshness.py`.
const int staleGraceMultiplier = 3;

class LocalBackend implements Backend {
  LocalBackend({Upstream? upstream, this._store})
      : _http = upstream ?? Upstream();

  final Upstream _http;

  /// Late bound, because opening the store needs an await a constructor
  /// cannot do. Injected directly in tests.
  JsonStore? _store;

  /// In flight refreshes, so two screens opening at once scrape once.
  final Map<String, Future<void>> _inFlight = {};

  static final Map<String, SourceSpec> sources = {
    'tigercenter_dining': SourceSpec(
      name: 'tigercenter_dining',
      cadence: const Duration(minutes: 60),
      scrape: scrapeDining,
    ),
    campusGroupsSource: SourceSpec(
      name: campusGroupsSource,
      cadence: const Duration(minutes: 180),
      scrape: scrapeCampusGroups,
    ),
    drupalSource: SourceSpec(
      name: drupalSource,
      cadence: const Duration(minutes: 180),
      scrape: scrapeDrupal,
    ),
    athleticsSource: SourceSpec(
      name: athleticsSource,
      cadence: const Duration(minutes: 180),
      scrape: scrapeAthletics,
    ),
  };

  Future<JsonStore> _openStore() async => _store ??= await JsonStore.open();

  /// Refresh [name] if its snapshot is older than its cadence. Never throws:
  /// a failed refresh leaves the previous snapshot in place, which is the
  /// offline first contract.
  Future<void> _refreshIfDue(String name, {bool force = false}) async {
    final spec = sources[name];
    if (spec == null) return;

    final store = await _openStore();
    if (!force) {
      final age = await store.fetchedAt(name);
      if (age != null &&
          DateTime.now().difference(age) < spec.cadence) {
        return;
      }
    }

    final running = _inFlight[name];
    if (running != null) return running;

    final future = () async {
      try {
        final payload = await spec.scrape(_http);
        await store.write(name, payload);
      } catch (_) {
        // Deliberately swallowed. The read path falls back to the stored
        // snapshot and reports staleness; a scrape failure must never surface
        // as an error screen over data we already hold.
      } finally {
        _inFlight.remove(name);
      }
    }();

    _inFlight[name] = future;
    return future;
  }

  /// The snapshot for [name], refreshing first only if nothing is stored yet.
  ///
  /// With a snapshot in hand the refresh is fired and not awaited, so the UI
  /// paints from cache immediately and updates when the scrape lands.
  Future<(Map<String, dynamic>?, DateTime?)> _snapshot(String name) async {
    final store = await _openStore();
    var stored = await store.read(name);

    if (stored == null) {
      await _refreshIfDue(name, force: true);
      stored = await store.read(name);
    } else {
      unawaited(_refreshIfDue(name));
    }

    return (stored?.body, stored?.fetchedAt);
  }

  /// Is this source's data missing or overdue? Mirrors `freshness.is_stale`.
  bool _isStale(String name, DateTime? fetchedAt) {
    if (fetchedAt == null) return true;
    final spec = sources[name];
    if (spec == null) return false;
    return DateTime.now().difference(fetchedAt) >
        spec.cadence * staleGraceMultiplier;
  }

  Map<String, dynamic> _envelope(
    String source,
    List<dynamic> data,
    DateTime? fetchedAt,
  ) =>
      {
        'data': data,
        'stale': _isStale(source, fetchedAt),
        'last_updated':
            fetchedAt == null ? null : CampusTime.format(fetchedAt.toUtc()),
      };

  @override
  Future<Map<String, dynamic>> fetch(
    String path,
    [Map<String, String>? query]
  ) async {
    await StaticConfig.load();

    switch (path) {
      case '/dining':
        return _dining(query);
      case '/dining/visiting-chefs':
        return _menuCategory(visitingChef);
      case '/dining/specials':
        return _menuCategory('Special');
      case '/events':
        return _events(query);
      case '/events/organizers':
        return _organizers();
    }

    throw UpstreamError('no local source serves $path');
  }

  Future<Map<String, dynamic>> _dining(Map<String, String>? query) async {
    final (snapshot, fetchedAt) = await _snapshot('tigercenter_dining');
    final now = CampusTime.nowUtc();
    final config = StaticConfig.instance;

    final locations = <Map<String, dynamic>>[
      for (final loc in snapshot?['locations'] as List<dynamic>? ?? const [])
        buildDiningLocation(loc as Map<String, dynamic>, now, config, null),
    ]..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    final data = query?['open_now'] == 'true'
        ? [for (final l in locations) if (l['is_open'] == true) l]
        : locations;

    return _envelope('tigercenter_dining', data, fetchedAt);
  }

  Future<Map<String, dynamic>> _menuCategory(String category) async {
    final (snapshot, fetchedAt) = await _snapshot('tigercenter_dining');
    final data = snapshot == null
        ? const <Map<String, dynamic>>[]
        : menuItemsWithCategory(snapshot, category);
    return _envelope('tigercenter_dining', data, fetchedAt);
  }

  /// Every event from all three feeds, with the freshness of the merged view.
  ///
  /// Either feed being cold makes the merged view incomplete, so staleness is
  /// the union and last_updated is the oldest of the two, matching the backend.
  Future<(List<Map<String, dynamic>>, bool, DateTime?)> _allEvents() async {
    final events = <Map<String, dynamic>>[];
    var stale = false;
    final stamps = <DateTime>[];

    for (final name in [campusGroupsSource, drupalSource, athleticsSource]) {
      final (snapshot, fetchedAt) = await _snapshot(name);
      for (final e in snapshot?['events'] as List<dynamic>? ?? const []) {
        events.add(e as Map<String, dynamic>);
      }
      // Athletics is a bonus feed; the merged view is not called incomplete
      // just because fixtures are cold, which is what the backend did.
      if (name != athleticsSource && _isStale(name, fetchedAt)) stale = true;
      if (fetchedAt != null && name != athleticsSource) stamps.add(fetchedAt);
    }

    stamps.sort();
    return (events, stale, stamps.isEmpty ? null : stamps.first);
  }

  Future<Map<String, dynamic>> _events(Map<String, String>? query) async {
    final (all, stale, updated) = await _allEvents();

    final days = int.tryParse(query?['days'] ?? '') ?? 14;
    final limit = int.tryParse(query?['limit'] ?? '') ?? 500;
    final begins = DateTime.tryParse(query?['start'] ?? '')?.toUtc() ??
        CampusTime.nowUtc();
    final ends = begins.add(Duration(days: days));

    final sources = _list(query?['source']);
    final organizers = _list(query?['organizer']);
    final muted = _list(query?['mute']);

    final matched = <Map<String, dynamic>>[];
    for (final event in all) {
      // Compared as instants, not as text. The three feeds store different
      // UTC offsets, so the backend's string comparison put an event with a
      // "-04:00" stamp in the wrong place relative to a "Z" one.
      final startsAt = DateTime.tryParse(event['starts_at'] as String? ?? '');
      if (startsAt == null) continue;
      final at = startsAt.toUtc();
      if (at.isBefore(begins) || !at.isBefore(ends)) continue;

      final source = event['source'] as String?;
      if (sources != null && !sources.contains(source)) continue;

      final key = event['organizer_key'] as String?;
      if (organizers != null && (key == null || !organizers.contains(key))) {
        continue;
      }
      if (muted != null && key != null && muted.contains(key)) continue;

      matched.add(event);
    }

    matched.sort((a, b) => DateTime.parse(a['starts_at'] as String)
        .toUtc()
        .compareTo(DateTime.parse(b['starts_at'] as String).toUtc()));

    return {
      'data': matched.take(limit).toList(),
      'stale': stale,
      'last_updated':
          updated == null ? null : CampusTime.format(updated.toUtc()),
    };
  }

  /// Facets for grouping, collapsing, or muting a noisy organizer.
  Future<Map<String, dynamic>> _organizers() async {
    final (all, stale, _) = await _allEvents();

    final counts = <String, Map<String, dynamic>>{};
    for (final event in all) {
      if (event['organizer'] == null) continue;
      final key = '${event['organizer_key']}\u0000${event['organizer']}'
          '\u0000${event['source']}';
      final row = counts.putIfAbsent(
        key,
        () => {
          'organizer_key': event['organizer_key'],
          'organizer': event['organizer'],
          'source': event['source'],
          'event_count': 0,
        },
      );
      row['event_count'] = (row['event_count'] as int) + 1;
    }

    final data = counts.values.toList()
      ..sort((a, b) =>
          (b['event_count'] as int).compareTo(a['event_count'] as int));

    return {'data': data, 'stale': stale, 'last_updated': null};
  }

  /// FastAPI took a repeated query parameter; the client sends one comma
  /// separated value, so both spellings are accepted.
  static List<String>? _list(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = [
      for (final p in raw.split(',')) if (p.trim().isNotEmpty) p.trim(),
    ];
    return parts.isEmpty ? null : parts;
  }

  @override
  void close() => _http.close();
}
