/// OpenStreetMap footprints are drawn only where RIT has none.
///
/// RIT's polygons are authoritative. These tests run the real bundled asset
/// against the real captured RIT building outlines and check that nothing is
/// drawn twice, and that the labelled building list never changes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/osm_features.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/osm_geometry.dart';

import 'map_repaint_test.dart' show RecordingCanvas, schemeOf;

const size = Size(400, 400);

List<Offset> square(double x, double y, double side) => [
  Offset(x, y),
  Offset(x + side, y),
  Offset(x + side, y + side),
  Offset(x, y + side),
];

void main() {
  final rit = parseCampusMapFeatures(
    File('test/fixtures/maps_category_3.data').readAsStringSync(),
  ).map(CampusMapFeature.fromJson).toList();
  final osm = OsmFeatures.parse(
    jsonDecode(File('assets/map/osm_features.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final projection = CampusMapProjection(rit, size);
  final ritBuilt = [
    for (final f in rit)
      if (f.geometryType != 'Point' && mapFamily(f).isBuilt)
        for (final ring in f.coordinates)
          if (ring.length >= 3) [for (final c in ring) projection.project(c)],
  ];
  final osmRings = [
    for (final ring in osm.building) [for (final c in ring) projection.project(c)],
  ];

  group('ring overlap', () {
    test('a ring crossing another overlaps it', () {
      expect(ringsOverlap(square(0, 0, 10), square(5, 5, 10)), isTrue);
    });

    test('a ring inside another overlaps it', () {
      expect(ringsOverlap(square(0, 0, 20), square(5, 5, 4)), isTrue);
      expect(ringsOverlap(square(5, 5, 4), square(0, 0, 20)), isTrue);
    });

    test('rings sharing a wall do not overlap', () {
      expect(ringsOverlap(square(0, 0, 10), square(10, 0, 10)), isFalse);
    });

    test('distant rings do not overlap', () {
      expect(ringsOverlap(square(0, 0, 10), square(50, 50, 10)), isFalse);
    });

    test('outsideRings drops only the rings that overlap', () {
      final kept = outsideRings(
        [square(0, 0, 10), square(50, 50, 10)],
        [square(5, 5, 10)],
      );
      expect(kept, hasLength(1));
      expect(kept.single.first, const Offset(50, 50));
    });
  });

  group('against the captured RIT outlines', () {
    test('the fixture has RIT buildings and the asset has footprints', () {
      expect(ritBuilt.length, greaterThan(100));
      expect(osmRings.length, greaterThan(100));
    });

    test('no kept footprint overlaps any RIT outline', () {
      final kept = outsideRings(osmRings, ritBuilt);
      for (final ring in kept) {
        for (final other in ritBuilt) {
          expect(ringsOverlap(ring, other), isFalse);
        }
      }
    });

    test('footprints RIT already draws are dropped, and new ones are kept', () {
      final kept = outsideRings(osmRings, ritBuilt);
      expect(kept.length, lessThan(osmRings.length));
      expect(kept, isNotEmpty);
    });

    test('every OSM footprint that overlaps RIT is among the dropped', () {
      final kept = outsideRings(osmRings, ritBuilt).toSet();
      for (final ring in osmRings) {
        final overlaps = ritBuilt.any((r) => ringsOverlap(ring, r));
        expect(kept.contains(ring), !overlaps);
      }
    });
  });

  group('painter', () {
    CampusMapPainter painter(OsmFeatures extras) => CampusMapPainter(
      features: rit,
      selectedId: null,
      scheme: schemeOf(Brightness.light),
      zoom: 8,
      osm: extras,
    );

    test('the labelled building list is unchanged by OSM footprints', () {
      final plain = painter(const OsmFeatures.empty());
      final withOsm = painter(osm);
      CampusMapPainter.resetGeometryCacheForTest();
      final before = plain.labelledBuildingIdsForTest(size);
      CampusMapPainter.resetGeometryCacheForTest();
      final after = withOsm.labelledBuildingIdsForTest(size);
      expect(after, before);
      expect(before, isNotEmpty);
    });

    test('footprints add one fill and one edge draw, no extra labels', () {
      CampusMapPainter.resetGeometryCacheForTest();
      final plain = RecordingCanvas();
      painter(const OsmFeatures.empty()).paint(plain, size);
      CampusMapPainter.resetGeometryCacheForTest();
      final withOsm = RecordingCanvas();
      painter(osm).paint(withOsm, size);
      final onlyFootprints = OsmFeatures(building: osm.building);
      CampusMapPainter.resetGeometryCacheForTest();
      final footprintsOnly = RecordingCanvas();
      painter(onlyFootprints).paint(footprintsOnly, size);
      expect(footprintsOnly.draws.length, plain.draws.length + 2);
      expect(withOsm.draws.length, greaterThan(plain.draws.length));
    });

    test('a footprint is never selectable', () {
      final features = rit.map((f) => f.id).toSet();
      final plain = painter(const OsmFeatures.empty());
      final withOsm = painter(osm);
      expect(withOsm.features.map((f) => f.id).toSet(), features);
      expect(plain.features.length, withOsm.features.length);
    });
  });
}
