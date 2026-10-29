/// The OpenStreetMap layers the walking paths do not cover, bundled.
///
/// Water, parks, pitches, building footprints RIT does not publish, entrances
/// and street names. Extracted once by `scripts/fetch-osm-features.py`, for
/// the same reasons as [CampusPaths]: the data is static and the map must work
/// with no network on a first launch.
///
/// It stays a separate file and is never merged into RIT's data. The ODbL
/// credit it requires is in the asset header, on the map legend, on the about
/// screen and in NOTICE, and must stay in all four.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/api_models.dart';

/// A door. Only some carry a name.
class OsmEntrance {
  const OsmEntrance(this.at, [this.name]);

  final GeoCoordinate at;
  final String? name;
}

/// A named street, as every way that carries the name.
class OsmStreet {
  const OsmStreet(this.name, this.lines);

  final String name;
  final List<List<GeoCoordinate>> lines;
}

class OsmFeatures {
  const OsmFeatures({
    this.water = const [],
    this.waterway = const [],
    this.park = const [],
    this.pitch = const [],
    this.building = const [],
    this.entrance = const [],
    this.street = const [],
  });

  const OsmFeatures.empty() : this();

  /// Filled rings: lakes and ponds.
  final List<List<GeoCoordinate>> water;

  /// Open lines: streams and creeks.
  final List<List<GeoCoordinate>> waterway;

  /// Filled rings: parks, lawns and other green space.
  final List<List<GeoCoordinate>> park;

  /// Filled rings: sports pitches. Never named.
  final List<List<GeoCoordinate>> pitch;

  /// Filled rings. Unlabeled. Drawn only where RIT has no footprint.
  final List<List<GeoCoordinate>> building;

  final List<OsmEntrance> entrance;
  final List<OsmStreet> street;

  bool get isEmpty =>
      water.isEmpty &&
      waterway.isEmpty &&
      park.isEmpty &&
      pitch.isEmpty &&
      building.isEmpty &&
      entrance.isEmpty &&
      street.isEmpty;

  static OsmFeatures? _cached;
  static Future<OsmFeatures>? _loading;

  /// Loads once per process, like [CampusPaths.load].
  static Future<OsmFeatures> load([AssetBundle? bundle]) {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _read(bundle ?? rootBundle).then((features) {
      _cached = features;
      _loading = null;
      return features;
    });
  }

  static Future<OsmFeatures> _read(AssetBundle bundle) async {
    try {
      final raw = await bundle.loadString('assets/map/osm_features.json');
      return parse(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A missing or unreadable asset must cost the extra layers, never the map.
      return const OsmFeatures.empty();
    }
  }

  static GeoCoordinate _point(dynamic p) =>
      GeoCoordinate((p[0] as num).toDouble(), (p[1] as num).toDouble());

  static List<GeoCoordinate> _line(dynamic way) => [
    for (final p in (way as List<dynamic>)) _point(p),
  ];

  /// Unknown keys are ignored. A key with the wrong shape empties the whole
  /// parse, so a half-read asset never draws.
  static OsmFeatures parse(Map<String, dynamic> json) {
    try {
      List<List<GeoCoordinate>> lines(String key) => [
        for (final way in (json[key] as List<dynamic>? ?? const [])) _line(way),
      ];
      return OsmFeatures(
        water: lines('water'),
        waterway: lines('waterway'),
        park: lines('park'),
        pitch: lines('pitch'),
        building: lines('building'),
        entrance: [
          for (final e in (json['entrance'] as List<dynamic>? ?? const []))
            OsmEntrance(
              _point(e),
              (e as List<dynamic>).length > 2 ? e[2] as String : null,
            ),
        ],
        street: [
          for (final s in (json['street'] as List<dynamic>? ?? const []))
            OsmStreet((s as Map<String, dynamic>)['name'] as String, [
              for (final way in (s['lines'] as List<dynamic>)) _line(way),
            ]),
        ],
      );
    } catch (_) {
      return const OsmFeatures.empty();
    }
  }

  /// Only for tests that need to start from nothing.
  static void resetForTest() {
    _cached = null;
    _loading = null;
  }
}
