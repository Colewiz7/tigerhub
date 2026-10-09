/// Live occupancy from maps.rit.edu.
///
/// Ported from `backend/app/scrapers/maps_occupancy.py`.
///
/// maps.rit.edu was rewritten as a Remix app, so the endpoint TigerDine used
/// (proxySearch/densityMapDetail.php) now 404s. The live data is at
/// `GET https://maps.rit.edu/details/<mdoId>.data` in Remix turbo-stream format.
///
/// This uses the **targeted** extractor rather than the general decoder in
/// `turbo_stream.dart`, matching the backend and docs/notes.md section 8 decision 1.
/// Only four fields plus a 24 hour series are needed out of one known object,
/// and walking from the densityData key to its immediate values is all that
/// takes. The general decoder exists for the campus map's category graph, which
/// genuinely needs it.
///
/// Failure here is contained: [parseOccupancy] returns null rather than
/// throwing, so a format change hides the occupancy chip instead of breaking
/// the dining response.
///
/// **Only 5 of 24 dining locations publish occupancy at all** (verified
/// 2026-08-28), so the other 19 are probed occasionally rather than every
/// cycle. On a server that saved thousands of pointless requests a day; on a
/// device it also saves the battery.
library;

import 'dart:convert';

import '../local_backend.dart' show ScrapeContext;
import '../upstream.dart';

const String occupancySource = 'maps_occupancy';
const String occupancyDetailsUrl = 'https://maps.rit.edu/details/{id}.data';

const int _maxDepth = 6;

/// Resolve one turbo-stream index into a plain Dart value.
Object? _resolve(List<dynamic> arr, Object? index, [int depth = 0]) {
  if (depth > _maxDepth || index is! int) return null;
  // Negative indices are turbo-stream sentinels (undefined, null, NaN).
  if (index < 0 || index >= arr.length) return null;

  final value = arr[index];

  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((rawKey, rawValue) {
      final key = '$rawKey';
      if (!key.startsWith('_')) return;
      final keyIndex = int.tryParse(key.substring(1));
      if (keyIndex == null) return;
      final resolved = _resolve(arr, keyIndex, depth + 1);
      if (resolved is String) out[resolved] = _resolve(arr, rawValue, depth + 1);
    });
    return out;
  }

  if (value is List) {
    return [for (final item in value) _resolve(arr, item, depth + 1)];
  }

  return value;
}

/// Pull densityData out of a turbo-stream payload. Null if not present.
Map<String, dynamic>? extractDensity(String raw) {
  final firstLine = raw.split('\n').first.trim();
  if (firstLine.isEmpty) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(firstLine);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;

  final keyIndex = decoded.indexOf('densityData');
  if (keyIndex < 0) return null;

  final marker = '_$keyIndex';
  for (final entry in decoded) {
    if (entry is Map && entry.containsKey(marker)) {
      final resolved = _resolve(decoded, entry[marker]);
      if (resolved is Map<String, dynamic>) return resolved;
    }
  }
  return null;
}

/// Normalize to the four things kept, plus the 24 hour series.
Map<String, dynamic>? parseOccupancy(String raw, int mdoId) {
  final density = extractDensity(raw);
  if (density == null || density.isEmpty) return null;

  final hourly = [
    for (final row in density['intra_loc_hours'] as List<dynamic>? ?? const [])
      if (row is Map<String, dynamic>)
        {
          'hour': row['hour'],
          'today': row['today'],
          'one_week_ago': row['one_week_ago'],
          'average': row['average'],
        },
  ];

  return {
    'mdo_id': density['mdo_id'] ?? mdoId,
    'count': density['count'],
    'max_occ': density['max_occ'],
    'open_status': density['open_status'],
    'hourly': hourly,
  };
}

/// What one occupancy request told us.
///
/// [answered] separates "the map server replied and this location has no
/// sensor" (a real answer, worth remembering for 12 hours) from "the request
/// failed, or a captive portal or error page came back with a 200" (no answer
/// at all, which must change nothing). Without the split a single bad poll
/// marked every location sensorless and dropped its last good reading.
typedef OccupancyProbe = ({bool answered, Map<String, dynamic>? reading});

/// Is [raw] shaped like the map's turbo-stream payload: a first line that is a
/// JSON array. An HTML login page is not.
bool looksLikeTurboStream(String raw) {
  final firstLine = raw.split('\n').first.trim();
  if (!firstLine.startsWith('[')) return false;
  try {
    return jsonDecode(firstLine) is List;
  } on FormatException {
    return false;
  }
}

Future<OccupancyProbe> probeOccupancy(Upstream http, int mdoId) async {
  try {
    final raw = await http.getText(
      occupancyDetailsUrl.replaceFirst('{id}', '$mdoId'),
    );
    if (!looksLikeTurboStream(raw)) return (answered: false, reading: null);
    return (answered: true, reading: parseOccupancy(raw, mdoId));
  } catch (_) {
    // One location failing never fails anything else.
    return (answered: false, reading: null);
  }
}

Future<Map<String, dynamic>?> fetchOccupancy(Upstream http, int mdoId) async =>
    (await probeOccupancy(http, mdoId)).reading;

/// How long before a location that reported no sensor is tried again.
///
/// The backend kept an `occupancy_probe` table for exactly this. Polling all 24
/// dining locations every 5 minutes is 6,912 requests a day for 5 useful
/// answers. Polling only the ones known to have a sensor is 1,440, and
/// re-probing the other 19 twice a day adds 38. RIT gets a twentieth of the
/// traffic and the app loses nothing.
const Duration occupancyReprobe = Duration(hours: 12);

/// How many already-probed locations to recheck in a single run.
///
/// Rechecks are speculative: a location that had no sensor yesterday almost
/// certainly has none today, and each response is about 226 KB. Capping them
/// spreads that cost out instead of re-downloading 5 MB twice a day.
///
/// The cap deliberately does **not** apply to locations that have never been
/// probed. Discovery is a one time cost, and until it finishes the app cannot
/// show occupancy for a location that has a sensor, so dragging it out over
/// twenty minutes of five minute cycles is worse than paying it at once. The
/// run is checkpointed after every location, so an interrupted first run
/// resumes rather than starting over.
const int occupancyReprobeBudget = 6;

/// Which locations to poll this run.
///
/// Known sensors first, since that is the actual feature and those answers are
/// what the UI is waiting on. Then everything never probed. Then a capped
/// number of rechecks.
List<int> occupancyPollList(
  List<int> allMdoIds,
  Map<String, dynamic> probes,
  DateTime now, {
  int reprobeBudget = occupancyReprobeBudget,
}) {
  final known = <int>[];
  final unprobed = <int>[];
  final rechecks = <int>[];

  for (final mdoId in allMdoIds) {
    final probe = probes['$mdoId'] as Map<String, dynamic>?;
    if (probe == null) {
      unprobed.add(mdoId);
      continue;
    }
    if (probe['has_density'] == true) {
      known.add(mdoId);
      continue;
    }
    final at = DateTime.tryParse(probe['probed_at'] as String? ?? '');
    if (at == null || now.difference(at) > occupancyReprobe) {
      rechecks.add(mdoId);
    }
  }

  return [...known, ...unprobed, ...rechecks.take(reprobeBudget)];
}

/// Poll the dining locations that actually publish occupancy.
///
/// Readings accumulate rather than being replaced wholesale: a location that
/// fails this run keeps its last reading, which is what the offline first rule
/// asks for. A location that reports no sensor has its reading dropped, because
/// that is a real answer rather than a failure.
Future<Map<String, dynamic>> scrapeOccupancy(ScrapeContext ctx) async {
  final dining = await ctx.snapshotOf('tigercenter_dining');
  final locations = dining?['locations'] as List<dynamic>? ?? const [];

  final mdoByLocation = <int, int>{};
  for (final raw in locations) {
    final loc = raw as Map<String, dynamic>;
    final mdoId = loc['mdo_id'];
    if (mdoId is int) mdoByLocation[loc['id'] as int] = mdoId;
  }
  if (mdoByLocation.isEmpty) {
    // Dining has not been scraped yet, so there is nothing to poll against.
    // Not an error: the next run will have it.
    return ctx.previous ?? {'readings': {}, 'probes': {}};
  }

  final readings = <String, dynamic>{
    ...?(ctx.previous?['readings'] as Map<String, dynamic>?),
  };
  final probes = <String, dynamic>{
    ...?(ctx.previous?['probes'] as Map<String, dynamic>?),
  };

  final now = DateTime.now();
  final due = occupancyPollList(mdoByLocation.values.toList(), probes, now);
  final stamp = now.toUtc().toIso8601String();

  for (final mdoId in due) {
    final probe = await probeOccupancy(ctx.http, mdoId);
    // No answer is not "no sensor": leave the probe and the reading alone.
    if (!probe.answered) continue;
    final reading = probe.reading;
    if (reading == null) {
      // Expected for most locations: they simply have no sensor.
      probes['$mdoId'] = {'has_density': false, 'probed_at': stamp};
      readings.remove('$mdoId');
    } else {
      probes['$mdoId'] = {'has_density': true, 'probed_at': stamp};
      readings['$mdoId'] = reading;
    }

    // Checkpoint after every location. These are 226 KB each and walked one at
    // a time, so a run can easily outlive the window being open. Saving as it
    // goes means discovery resumes instead of restarting from nothing.
    await ctx.save({'readings': readings, 'probes': probes});
  }

  return {'readings': readings, 'probes': probes};
}
