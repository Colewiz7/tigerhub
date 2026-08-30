/// The bundled walking network.
///
/// maps.rit.edu has no line geometry at all, so without this the map can show
/// buildings and pins but nothing about how you get between them. The data is
/// OpenStreetMap, extracted once by `scripts/fetch-osm-paths.py`.
///
/// These tests guard the asset itself, because it is generated and committed
/// rather than fetched, so nothing else would notice if it were truncated,
/// re-extracted with the wrong bounds, or stripped of its licence.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';

void main() {
  final raw =
      jsonDecode(File('assets/map/paths.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the asset still carries its ODbL credit', () {
    // This is a licence obligation, not decoration. If a regeneration ever
    // drops it, the app is redistributing OSM data uncredited.
    expect(raw['attribution'], contains('OpenStreetMap'));
    expect(raw['attribution'], contains('ODbL'));
    expect(raw['source'], contains('openstreetmap.org/copyright'));
    expect(raw['last_verified'], isNotEmpty);
  });

  test('it holds a real network, not a stub', () {
    final paths = CampusPaths.parse(raw);
    expect(paths.foot.length, greaterThan(1000));
    expect(paths.road.length, greaterThan(400));
    expect(paths.isEmpty, isFalse);
  });

  test('every way has at least two ends', () {
    final paths = CampusPaths.parse(raw);
    for (final way in [...paths.foot, ...paths.road]) {
      expect(way.length, greaterThanOrEqualTo(2));
    }
  });

  test('nothing strayed outside the campus box', () {
    // The extract is clipped so a path leaving the box keeps only the part on
    // campus. A stray node would stretch the fitted view back out.
    final box = raw['bbox'] as Map<String, dynamic>;
    final west = (box['west'] as num).toDouble();
    final east = (box['east'] as num).toDouble();
    final south = (box['south'] as num).toDouble();
    final north = (box['north'] as num).toDouble();

    final paths = CampusPaths.parse(raw);
    for (final way in [...paths.foot, ...paths.road]) {
      for (final point in way) {
        expect(point.longitude, inInclusiveRange(west, east));
        expect(point.latitude, inInclusiveRange(south, north));
      }
    }
  });

  test('it stays small enough to bundle', () {
    // 114 KB at the 2.2m simplification. Well over this means the simplify or
    // clip step was skipped, and the app is shipping raw OSM.
    final bytes = File('assets/map/paths.json').lengthSync();
    expect(bytes, lessThan(200 * 1024), reason: '${bytes ~/ 1024} KB is too big');
  });

  test('a broken asset costs the paths, never the map', () {
    // The map has to keep working with no paths at all, the same way it has to
    // keep working with no network.
    expect(CampusPaths.parse(const {}).isEmpty, isTrue);
    expect(const CampusPaths.empty().isEmpty, isTrue);
  });

  test('the app credits OpenStreetMap where a user can see it', () {
    // ODbL requires the credit to travel with the data. The asset header is
    // not enough on its own, since nobody opening the app reads it.
    final about = File('lib/screens/settings/about_section.dart')
        .readAsStringSync();
    expect(about, contains('OpenStreetMap'));
    expect(about, contains('ODbL'));
  });
}
