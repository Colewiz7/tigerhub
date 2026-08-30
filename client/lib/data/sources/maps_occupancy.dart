/// Live occupancy from maps.rit.edu.
///
/// Ported from `backend/app/scrapers/maps_occupancy.py`.
///
/// maps.rit.edu was rewritten as a Remix app, so the endpoint TigerDine used
/// (proxySearch/densityMapDetail.php) now 404s. The live data is at
/// `GET https://maps.rit.edu/details/<mdoId>.data` in Remix turbo-stream format.
///
/// This uses the **targeted** extractor rather than the general decoder in
/// `turbo_stream.dart`, matching the backend and CLAUDE.md section 8 decision 1.
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

Future<Map<String, dynamic>?> fetchOccupancy(Upstream http, int mdoId) async {
  try {
    final raw = await http.getText(
      occupancyDetailsUrl.replaceFirst('{id}', '$mdoId'),
    );
    return parseOccupancy(raw, mdoId);
  } catch (_) {
    // One location failing never fails anything else.
    return null;
  }
}
