/// The campus walking network, bundled rather than fetched.
///
/// maps.rit.edu publishes no line geometry at all: every one of its categories
/// is Point or Polygon, so the map could draw buildings and pins but nothing
/// that showed how you get between them. The paths come from OpenStreetMap
/// instead, extracted once by `scripts/fetch-osm-paths.py`.
///
/// It ships as an asset instead of a live source because the walking network
/// does not change, and because CLAUDE.md 3.1 requires the app to work with no
/// network on a first launch. A path you can only see after a successful fetch
/// is exactly the thing that fails while you are standing outside in the cold.
///
/// The data is ODbL. The credit it requires is in the asset header and on the
/// about screen, and must stay in both.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/api_models.dart';

class CampusPaths {
  const CampusPaths({required this.foot, required this.road});

  const CampusPaths.empty() : foot = const [], road = const [];

  /// Footways, steps, and cycleways. The useful half on a campus you cross on
  /// foot, so these are drawn more clearly than the roads.
  final List<List<GeoCoordinate>> foot;

  /// Service roads and streets. Context, drawn wider but fainter.
  final List<List<GeoCoordinate>> road;

  bool get isEmpty => foot.isEmpty && road.isEmpty;

  static CampusPaths? _cached;
  static Future<CampusPaths>? _loading;

  /// Loads once per process. The asset is 114 KB of JSON, which is worth
  /// decoding a single time and holding.
  static Future<CampusPaths> load([AssetBundle? bundle]) {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _read(bundle ?? rootBundle).then((paths) {
      _cached = paths;
      _loading = null;
      return paths;
    });
  }

  static Future<CampusPaths> _read(AssetBundle bundle) async {
    try {
      final raw = await bundle.loadString('assets/map/paths.json');
      return parse(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A missing or unreadable asset must cost the paths, never the map.
      return const CampusPaths.empty();
    }
  }

  static CampusPaths parse(Map<String, dynamic> json) {
    List<List<GeoCoordinate>> lines(String key) => [
      for (final way in (json[key] as List<dynamic>? ?? const []))
        [
          for (final point in (way as List<dynamic>))
            GeoCoordinate(
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ),
        ],
    ];
    return CampusPaths(foot: lines('foot'), road: lines('road'));
  }

  /// Only for tests that need to start from nothing.
  static void resetForTest() {
    _cached = null;
    _loading = null;
  }
}
