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
import 'merge_events.dart';
import 'sources/athletics.dart';
import 'sources/campus_places.dart';
import 'sources/campusgroups.dart';
import 'sources/drupal_events.dart';
import 'sources/fd_menus.dart';
import 'sources/makerspace.dart';
import 'sources/maps_occupancy.dart';
import 'sources/recreation.dart';
import 'sources/tigercenter.dart';
import 'static_config.dart';
import 'store.dart';
import 'upstream.dart';

/// What a scrape is handed.
///
/// Most sources need only [http]. Occupancy needs the rest: it has to know
/// which locations exist (from the dining snapshot) and which of them were
/// found to have a sensor last time (from its own [previous] snapshot), so it
/// polls five locations rather than twenty four.
class ScrapeContext {
  const ScrapeContext({
    required this.http,
    required this.previous,
    required this.save,
    required this.snapshotOf,
    required this.config,
  });

  final Upstream http;

  /// This source's last stored snapshot, if any.
  final Map<String, dynamic>? previous;

  /// Persist progress mid scrape.
  ///
  /// A scrape that only saves at the end loses everything if the app closes
  /// first. Occupancy discovery is the case that needs it: it walks locations
  /// one at a time and would otherwise restart from nothing on every launch.
  final Future<void> Function(Map<String, dynamic>) save;

  /// Another source's last stored snapshot, without triggering its refresh.
  final Future<Map<String, dynamic>?> Function(String) snapshotOf;

  final StaticConfig config;
}

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
  final Future<Map<String, dynamic>> Function(ScrapeContext) scrape;
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

  /// Decoded snapshots, kept in memory.
  ///
  /// The stored payloads total about 2 MB, and events alone is nearly a
  /// megabyte of JSON. Re-reading and re-decoding that on every read would be
  /// visible as jank, and the periodic refresh makes reads frequent, so a
  /// decoded copy is held and replaced only when a scrape writes.
  final Map<String, (Map<String, dynamic>, DateTime)> _memory = {};

  static final Map<String, SourceSpec> sources = {
    'tigercenter_dining': SourceSpec(
      name: 'tigercenter_dining',
      cadence: const Duration(minutes: 60),
      scrape: (ctx) => scrapeDining(ctx.http),
    ),
    campusGroupsSource: SourceSpec(
      name: campusGroupsSource,
      cadence: const Duration(minutes: 180),
      scrape: (ctx) => scrapeCampusGroups(ctx.http),
    ),
    drupalSource: SourceSpec(
      name: drupalSource,
      cadence: const Duration(minutes: 180),
      scrape: (ctx) => scrapeDrupal(ctx.http),
    ),
    athleticsSource: SourceSpec(
      name: athleticsSource,
      cadence: const Duration(minutes: 180),
      scrape: (ctx) => scrapeAthletics(ctx.http),
    ),
    makerspaceSource: SourceSpec(
      name: makerspaceSource,
      cadence: const Duration(minutes: 15),
      scrape: (ctx) => scrapeMakerspace(ctx.http),
    ),
    campusPlacesSource: SourceSpec(
      name: campusPlacesSource,
      // Physical infrastructure. It changes rarely, so twice a day.
      cadence: const Duration(minutes: 720),
      scrape: (ctx) => scrapeCampusPlaces(ctx.http),
    ),
    recreationSource: SourceSpec(
      name: recreationSource,
      cadence: const Duration(minutes: 360),
      scrape: (ctx) => scrapeRecreation(ctx.http),
    ),
    occupancySource: SourceSpec(
      name: occupancySource,
      cadence: const Duration(minutes: 5),
      scrape: scrapeOccupancy,
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
      final held = _memory[name];
      final age = held?.$2 ?? await store.fetchedAt(name);
      if (age != null && DateTime.now().difference(age) < spec.cadence) {
        return;
      }
    }

    final running = _inFlight[name];
    if (running != null) return running;

    Future<void> persist(Map<String, dynamic> payload) async {
      await store.write(name, payload);
      _memory[name] = (payload, DateTime.now());
    }

    final future = () async {
      try {
        final previous = await _cachedRead(name);
        final payload = await spec.scrape(
          ScrapeContext(
            http: _http,
            previous: previous?.$1,
            save: persist,
            snapshotOf: (other) async => (await _cachedRead(other))?.$1,
            config: StaticConfig.instance,
          ),
        );
        await persist(payload);
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

  /// A snapshot from memory, falling back to disk once.
  Future<(Map<String, dynamic>, DateTime)?> _cachedRead(String name) async {
    final held = _memory[name];
    if (held != null) return held;

    final store = await _openStore();
    final stored = await store.read(name);
    if (stored == null) return null;

    final entry = (stored.body, stored.fetchedAt);
    _memory[name] = entry;
    return entry;
  }

  /// The snapshot for [name], refreshing first only if nothing is stored yet.
  ///
  /// With a snapshot in hand the refresh is fired and not awaited, so the UI
  /// paints from cache immediately and updates when the scrape lands.
  Future<(Map<String, dynamic>?, DateTime?)> _snapshot(String name) async {
    var stored = await _cachedRead(name);

    if (stored == null) {
      await _refreshIfDue(name, force: true);
      stored = await _cachedRead(name);
    } else {
      unawaited(_refreshIfDue(name));
    }

    return (stored?.$1, stored?.$2);
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
  ) => {
    'data': data,
    'stale': _isStale(source, fetchedAt),
    'last_updated': fetchedAt == null
        ? null
        : CampusTime.format(fetchedAt.toUtc()),
  };

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    await StaticConfig.load();

    switch (path) {
      case '/dining':
        return _dining(query);
      case '/dining/visiting-chefs':
        return _menuCategory(visitingChef);
      case '/dining/specials':
        // Everything on today's menu, not a category called "Special".
        return _menuCategory(null);
      case '/events':
        return _events(query);
      case '/events/organizers':
        return _organizers();
      case '/makerspace/equipment':
        return _equipment(query);
      case '/makerspace/rooms':
        return _rooms();
      case '/makerspace/hours':
        return _shedHours();
      case '/recreation/hours':
        return _recreation();
      case '/campus/places':
        return _placeKinds();
      case '/campus/map':
        return _campusMap();
      case '/post-offices':
        return _postOffices();
      case '/housing/areas':
        return _housingAreas();
    }

    final places = RegExp(r'^/campus/places/([A-Za-z0-9_]+)$').firstMatch(path);
    if (places != null) return _places(places.group(1)!);

    final menu = RegExp(r'^/dining/(\d+)/menu$').firstMatch(path);
    if (menu != null) return _menu(int.parse(menu.group(1)!));

    final occupancy = RegExp(r'^/dining/(\d+)/occupancy$').firstMatch(path);
    if (occupancy != null) return _occupancy(int.parse(occupancy.group(1)!));

    final address = RegExp(r'^/housing/areas/([A-Za-z0-9_-]+)/address$')
        .firstMatch(path);
    if (address != null) return _address(address.group(1)!, query);

    throw UpstreamError('no local source serves $path');
  }

  Future<Map<String, dynamic>> _dining(Map<String, String>? query) async {
    final (snapshot, fetchedAt) = await _snapshot('tigercenter_dining');
    final now = CampusTime.nowUtc();
    final config = StaticConfig.instance;

    // Occupancy is joined on mdo_id, the way the server joined its two tables.
    // Without this the pill never renders, "busiest first" cannot sort, and the
    // history sheet never opens, which is most of what the feature is.
    final (occupancy, _) = await _snapshot(occupancySource);
    final readings =
        occupancy?['readings'] as Map<String, dynamic>? ?? const {};

    final locations = <Map<String, dynamic>>[
      for (final loc in snapshot?['locations'] as List<dynamic>? ?? const [])
        buildDiningLocation(
          loc as Map<String, dynamic>,
          now,
          config,
          readings['${loc['mdo_id']}'] as Map<String, dynamic>?,
        ),
    ]..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    final data = query?['open_now'] == 'true'
        ? [
            for (final l in locations)
              if (l['is_open'] == true) l,
          ]
        : locations;

    return _envelope('tigercenter_dining', data, fetchedAt);
  }

  Future<Map<String, dynamic>> _menuCategory(String? category) async {
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
    final begins =
        DateTime.tryParse(query?['start'] ?? '')?.toUtc() ??
        CampusTime.nowUtc();
    final ends = begins.add(Duration(days: days));

    final sources = _list(query?['source']);
    final organizers = _list(query?['organizer']);
    final muted = _list(query?['mute']);

    // Window first, then merge, then the user's filters.
    //
    // The order matters. Merging after an organizer filter would be useless,
    // because the filter would already have kept one copy and dropped the
    // other, leaving nothing to merge. And filtering before merging would test
    // the Drupal copy's "RIT" organizer rather than the club's.
    final inWindow = <Map<String, dynamic>>[];
    for (final event in all) {
      // Compared as instants, not as text. The three feeds store different
      // UTC offsets, so the backend's string comparison put an event with a
      // "-04:00" stamp in the wrong place relative to a "Z" one.
      final startsAt = DateTime.tryParse(event['starts_at'] as String? ?? '');
      if (startsAt == null) continue;
      final at = startsAt.toUtc();
      if (at.isBefore(begins) || !at.isBefore(ends)) continue;
      inWindow.add(event);
    }

    final matched = <Map<String, dynamic>>[];
    for (final event in mergeDuplicateEvents(inWindow)) {
      final source = event['source'] as String?;
      if (sources != null && !sources.contains(source)) continue;

      final key = event['organizer_key'] as String?;
      if (organizers != null && (key == null || !organizers.contains(key))) {
        continue;
      }
      if (muted != null && key != null && muted.contains(key)) continue;

      matched.add(event);
    }

    matched.sort(
      (a, b) =>
          DateTime.parse(a['starts_at'] as String)
              .toUtc()
              .compareTo(DateTime.parse(b['starts_at'] as String).toUtc()),
    );

    return {
      'data': matched.take(limit).toList(),
      'stale': stale,
      'last_updated': updated == null
          ? null
          : CampusTime.format(updated.toUtc()),
    };
  }

  /// Facets for grouping, collapsing, or muting a noisy organizer.
  Future<Map<String, dynamic>> _organizers() async {
    final (all, stale, _) = await _allEvents();

    // Merged, so the rail's counts match the list it jumps to.
    final counts = <String, Map<String, dynamic>>{};
    for (final event in mergeDuplicateEvents(all)) {
      if (event['organizer'] == null) continue;
      final key =
          '${event['organizer_key']}\u0000${event['organizer']}'
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
      ..sort(
        (a, b) => (b['event_count'] as int).compareTo(a['event_count'] as int),
      );

    return {'data': data, 'stale': stale, 'last_updated': null};
  }

  /// FastAPI took a repeated query parameter; the client sends one comma
  /// separated value, so both spellings are accepted.
  static List<String>? _list(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = [
      for (final p in raw.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    return parts.isEmpty ? null : parts;
  }

  // --- makerspace ---

  Future<Map<String, dynamic>> _equipment(Map<String, String>? query) async {
    final (snapshot, fetchedAt) = await _snapshot(makerspaceSource);
    return _envelope(
      makerspaceSource,
      equipmentIn(snapshot, query?['room']),
      fetchedAt,
    );
  }

  Future<Map<String, dynamic>> _rooms() async {
    final (snapshot, fetchedAt) = await _snapshot(makerspaceSource);
    return _envelope(makerspaceSource, roomSummary(snapshot), fetchedAt);
  }

  /// SHED hours are static config, not a scrape. Their own hours feed returns
  /// closed:true on every row with an ISO timestamp where a weekday belongs
  /// (CLAUDE.md 8, decision 3).
  ///
  /// This endpoint returned a bare list rather than an envelope, so it is
  /// wrapped as items to match what watchList expects.
  Future<Map<String, dynamic>> _shedHours() async => {
    'items': StaticConfig.instance.shedSpaces,
  };

  // --- recreation ---

  Future<Map<String, dynamic>> _recreation() async {
    final (snapshot, fetchedAt) = await _snapshot(recreationSource);
    return _envelope(
      recreationSource,
      recreationFacilities(snapshot),
      fetchedAt,
    );
  }

  // --- campus places ---

  Future<Map<String, dynamic>> _placeKinds() async {
    final (snapshot, fetchedAt) = await _snapshot(campusPlacesSource);
    return _envelope(campusPlacesSource, placeKindSummary(snapshot), fetchedAt);
  }

  Future<Map<String, dynamic>> _places(String kind) async {
    final (snapshot, fetchedAt) = await _snapshot(campusPlacesSource);
    return _envelope(
      campusPlacesSource,
      placesOfKind(snapshot, kind),
      fetchedAt,
    );
  }

  Future<Map<String, dynamic>> _campusMap() async {
    var (snapshot, fetchedAt) = await _snapshot(campusPlacesSource);
    // Snapshots written before the map shipped contain the place lists but no
    // geometry. They can keep serving every existing screen, but the first map
    // visit needs one migration refresh even when that old snapshot is fresh.
    final mapFeatures = snapshot?['map_features'] as List<dynamic>?;
    final hasBackdrop =
        mapFeatures?.any(
          (feature) =>
              feature is Map<String, dynamic> && feature['kind'] == '_campus',
        ) ??
        false;
    if (snapshot != null && !hasBackdrop) {
      await _refreshIfDue(campusPlacesSource, force: true);
      final refreshed = await _cachedRead(campusPlacesSource);
      snapshot = refreshed?.$1;
      fetchedAt = refreshed?.$2;
    }
    return _envelope(
      campusPlacesSource,
      campusMapFeatures(snapshot),
      fetchedAt,
    );
  }

  // --- static config ---

  Future<Map<String, dynamic>> _postOffices() async => {
    'data': StaticConfig.instance.postOffices,
    'stale': false,
    'last_updated': null,
  };

  /// Mail zones, including the two locations that bypass campus post offices.
  Future<Map<String, dynamic>> _housingAreas() async {
    final config = StaticConfig.instance;
    return {
      'data': [
        for (final area in config.housingAreas)
          {
            'id': area['id'],
            'name': area['name'],
            'post_office': area['post_office'],
            'line2_format': area['line2_format'],
            'line2_example': area['line2_example'],
            'last_verified': area['last_verified'],
          },
        for (final delivered in config.directDelivery)
          {
            'id': delivered['id'],
            'name': delivered['name'],
            'direct_delivery': true,
            'last_verified': delivered['last_verified'],
          },
      ],
      'stale': false,
      'last_updated': null,
    };
  }

  Future<Map<String, dynamic>> _address(
    String areaId,
    Map<String, String>? query,
  ) async {
    final config = StaticConfig.instance;
    final name = query?['name'] ?? 'Your Name';
    final unit = query?['unit'];

    final lines = config.addressFor(areaId, name, unit);
    if (lines == null) throw UpstreamError('housing area not found: $areaId');

    final delivered = config.direct(areaId);
    if (delivered != null) {
      return {
        'area_id': delivered['id'],
        'area_name': delivered['name'],
        'lines': lines,
        'unit_supplied': true,
        'direct_delivery': true,
        'note': delivered['note'],
        'source_url': config.housingSourceUrl,
        'last_verified': delivered['last_verified'],
        'verified': delivered['last_verified'] != null,
      };
    }

    final area = config.area(areaId)!;
    return {
      'area_id': area['id'],
      'area_name': area['name'],
      'lines': lines,
      'line2_format': area['line2_format'],
      'line2_example': area['line2_example'],
      'unit_supplied': unit != null,
      'post_office': config.office(area['post_office'] as String?),
      'source_url': config.housingSourceUrl,
      'last_verified': area['last_verified'],
      'verified': area['last_verified'] != null,
    };
  }

  // --- per location, fetched on demand ---

  /// Occupancy for one location. Only 5 of 24 publish it, and a location with
  /// no sensor is the normal case rather than an error.
  Future<Map<String, dynamic>> _occupancy(int locationId) async {
    final (dining, _) = await _snapshot('tigercenter_dining');
    int? mdoId;
    for (final raw in dining?['locations'] as List<dynamic>? ?? const []) {
      final loc = raw as Map<String, dynamic>;
      if (loc['id'] == locationId) mdoId = loc['mdo_id'] as int?;
    }
    if (mdoId == null) {
      throw UpstreamError('no mdo_id for location $locationId');
    }

    // The polling source already holds a recent reading for every location
    // that has a sensor, so the detail sheet reuses it rather than issuing its
    // own 226 KB request every time a row is tapped.
    final (occupancy, fetchedAt) = await _snapshot(occupancySource);
    final reading =
        (occupancy?['readings'] as Map<String, dynamic>?)?['$mdoId'];

    if (reading is Map<String, dynamic>) {
      return {
        ...reading,
        'stale': _isStale(occupancySource, fetchedAt),
        'last_updated': fetchedAt == null
            ? null
            : CampusTime.format(fetchedAt.toUtc()),
      };
    }

    throw UpstreamError('no occupancy reading for this location');
  }

  /// A location's menu for today, fetched on demand rather than rotated.
  ///
  /// See the payload note in `sources/fd_menus.dart`: this asks for one day
  /// rather than a month, which is about 1 MB instead of 26 MB per meal period.
  ///
  /// A stored menu paints immediately and the refresh runs behind it, the same
  /// as every other read. Blocking here would freeze the detail sheet on a
  /// network round trip every time a row is tapped.
  Future<Map<String, dynamic>> _menu(int locationId) async {
    final config = StaticConfig.instance;
    final key = 'fd_menus_$locationId';
    final store = await _openStore();
    final today = CampusTime.formatDate(CampusTime.nowUtc());

    final stored = await store.read(key);
    final age = await store.fetchedAt(key);

    // A snapshot for another date is useless no matter how recent it is, which
    // is what happens to anyone opening the app just after midnight.
    final wrongDay = stored != null && stored.body['service_date'] != today;
    final due =
        stored == null ||
        wrongDay ||
        age == null ||
        DateTime.now().difference(age) > fdMenuCadence;

    Future<void> refresh() async {
      if (_inFlight.containsKey(key)) return _inFlight[key];
      final future = () async {
        try {
          final fetched = await fetchFdMenus(_http, config, locationId);
          if (fetched != null) await store.write(key, fetched);
        } catch (_) {
          // Falls back to whatever is stored, or to an empty menu.
        } finally {
          _inFlight.remove(key);
        }
      }();
      _inFlight[key] = future;
      return future;
    }

    var body = stored?.body;

    if (due) {
      if (body == null || wrongDay) {
        // Nothing usable to show, so this one has to be waited on.
        await refresh();
        body = (await store.read(key))?.body;
      } else {
        unawaited(refresh());
      }
    }

    return {
      'service_date': today,
      'location_id': locationId,
      'dishes': dishesOn(body, today),
      'stale': body == null || body['service_date'] != today,
      'last_updated': age == null ? null : CampusTime.format(age.toUtc()),
    };
  }

  @override
  void close() => _http.close();
}
