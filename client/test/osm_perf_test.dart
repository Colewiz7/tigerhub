/// What the OpenStreetMap layers cost: geometry builds, draw calls, time.
///
/// The map paints in unzoomed coordinates inside the viewer and never learns
/// the pan, so it cannot cull in Dart. Each layer is therefore one path, and
/// these tests hold that: the draw count stays small however many shapes there
/// are, and the geometry is built once per set of inputs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';
import 'package:tigerhub/data/osm_features.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';

import 'golden_harness.dart';
import 'map_repaint_test.dart' show RecordingCanvas, schemeOf;

const size = Size(390, 520);
const zooms = [1.0, 3.0, 8.0, 20.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGoldenFonts);

  final features = [
    for (final n in ['3', '11', '35'])
      ...parseCampusMapFeatures(
        File('test/fixtures/maps_category_$n.data').readAsStringSync(),
      ).map(CampusMapFeature.fromJson),
  ];
  final paths = CampusPaths.parse(
    jsonDecode(File('assets/map/paths.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  OsmFeatures loadOsm() => OsmFeatures.parse(
    jsonDecode(File('assets/map/osm_features.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final osm = loadOsm();

  CampusMapPainter painter(double zoom, {OsmFeatures? extras, int? selectedId}) =>
      CampusMapPainter(
        features: features,
        selectedId: selectedId,
        scheme: schemeOf(Brightness.light),
        zoom: zoom,
        paths: paths,
        osm: extras ?? osm,
      );

  RecordingCanvas draw(CampusMapPainter p) {
    final canvas = RecordingCanvas();
    p.paint(canvas, size);
    return canvas;
  }

  setUp(CampusMapPainter.resetGeometryCacheForTest);

  group('geometry builds', () {
    int builds(void Function() body) {
      final before = CampusMapPainter.geometryBuilds;
      body();
      return CampusMapPainter.geometryBuilds - before;
    }

    test('every zoom and a selection change reuse one build', () {
      expect(
        builds(() {
          for (final zoom in [...zooms, 1.5, 2.5, 5.0, 12.0]) {
            draw(painter(zoom));
          }
          draw(painter(8, selectedId: features.first.id));
        }),
        1,
      );
    });

    test('the same OSM instance reuses it, a new one builds once', () {
      expect(
        builds(() {
          draw(painter(3));
          draw(painter(3));
        }),
        1,
      );
      expect(
        builds(() {
          draw(painter(3, extras: loadOsm()));
          draw(painter(3, extras: loadOsm()));
        }),
        2,
        reason: 'two distinct instances are two distinct inputs',
      );
    });

    test('a layout that cannot be repainted for nothing', () {
      final a = painter(3);
      expect(a.shouldRepaint(painter(3)), isFalse);
      expect(a.shouldRepaint(painter(3, extras: const OsmFeatures.empty())), isTrue);
    });
  });

  group('draw calls', () {
    test('stay small at every zoom however many shapes there are', () {
      final counts = <double, int>{};
      for (final zoom in zooms) {
        counts[zoom] = draw(painter(zoom)).draws.length;
      }
      // ignore: avoid_print
      print('draw calls at 1x/3x/8x/20x: ${counts.values.toList()}');
      final shapes =
          osm.water.length +
          osm.waterway.length +
          osm.park.length +
          osm.pitch.length +
          osm.building.length +
          osm.entrance.length +
          features.length;
      expect(shapes, greaterThan(800));
      for (final entry in counts.entries) {
        // measured at 27 to 32, so a layer that stops being one path shows up
        expect(entry.value, lessThan(45), reason: 'zoom ${entry.key}');
      }
    });

    test('the OSM layers add a fixed handful, not one per shape', () {
      for (final zoom in zooms) {
        final without = draw(painter(zoom, extras: const OsmFeatures.empty())).draws.length;
        final withOsm = draw(painter(zoom)).draws.length;
        expect(withOsm - without, lessThanOrEqualTo(12), reason: 'zoom $zoom');
        expect(withOsm - without, greaterThan(0), reason: 'zoom $zoom');
      }
    });

    test('all the entrances are two draw calls', () {
      expect(osm.entrance.length, greaterThan(100));
      for (final zoom in const [8.0, 20.0]) {
        final dots = draw(painter(zoom)).draws.where((d) => d.kind == 'points');
        expect(dots, hasLength(2), reason: 'zoom $zoom');
      }
    });
  });

  group('time', () {
    test('a cold geometry build stays under budget', () {
      CampusMapPainter.resetGeometryCacheForTest();
      final watch = Stopwatch()..start();
      draw(painter(1));
      watch.stop();
      // ignore: avoid_print
      print('cold build and first paint: ${watch.elapsedMilliseconds} ms');
      // a few milliseconds here, with a wide margin for a slow CI machine
      expect(watch.elapsedMilliseconds, lessThan(300));
    });

    test('replanning labels at each zoom step stays under budget', () {
      // the ink cache is warm after the first plan, as it is in the app
      painter(20).labelPlanForTest(size);
      final steps = [for (var z = 1.0; z <= 20; z *= 1.25) z];
      final watch = Stopwatch()..start();
      for (final z in steps) {
        painter(z).labelPlanForTest(size);
      }
      watch.stop();
      final each = watch.elapsedMilliseconds / steps.length;
      // ignore: avoid_print
      print('label replan: ${each.toStringAsFixed(1)} ms per quarter-zoom step over ${steps.length} steps');
      expect(each, lessThan(40));
    });

    test('a warm repaint is cheap', () {
      draw(painter(8));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        draw(painter(8));
      }
      watch.stop();
      final each = watch.elapsedMilliseconds / 20;
      // ignore: avoid_print
      print('warm repaint: ${each.toStringAsFixed(1)} ms');
      expect(each, lessThan(40));
    });
  });
}
