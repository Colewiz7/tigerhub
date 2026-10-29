/// OpenStreetMap entrances: a dot from 8x, a name only at 20x.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/osm_features.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_labels.dart';
import 'package:tigerhub/widgets/map_style.dart';

import 'golden_harness.dart';
import 'map_repaint_test.dart'
    show Draw, RecordingCanvas, features, near, schemeOf;

const size = Size(400, 400);

// inside the test polygons, which run from -77.678 to -77.669
const door = GeoCoordinate(-77.6745, 43.0845);
const nearby = GeoCoordinate(-77.67395, 43.08458);

CampusMapFeature accessibleEntrance(GeoCoordinate at) => CampusMapFeature(
  id: 900,
  kind: 'entrance_accessible',
  kindName: 'Accessible entrance',
  name: 'Entrance',
  geometryType: 'Point',
  coordinates: [
    [at],
  ],
);

OsmFeatures doors(List<OsmEntrance> entrance) =>
    OsmFeatures(entrance: entrance);

CampusMapPainter painter(
  OsmFeatures osm, {
  required double zoom,
  Brightness brightness = Brightness.light,
  List<CampusMapFeature>? extra,
}) => CampusMapPainter(
  features: [...features, ...?extra],
  selectedId: null,
  scheme: schemeOf(brightness),
  zoom: zoom,
  osm: osm,
);

RecordingCanvas draw(CampusMapPainter p) {
  CampusMapPainter.resetGeometryCacheForTest();
  final canvas = RecordingCanvas();
  p.paint(canvas, size);
  return canvas;
}

Iterable<Draw> dotsOf(RecordingCanvas c) =>
    c.draws.where((d) => d.kind == 'points');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final osm = doors(const [
    OsmEntrance(door, 'Main entrance'),
    OsmEntrance(GeoCoordinate(-77.673, 43.0842)),
  ]);

  for (final brightness in const [Brightness.light, Brightness.dark]) {
    final palette = MapPalette.of(brightness);

    group('dots, ${brightness.name}', () {
      test('hidden at 1x and 3x, drawn at 8x and 20x', () {
        for (final zoom in const [1.0, 3.0]) {
          expect(
            dotsOf(draw(painter(osm, zoom: zoom, brightness: brightness))),
            isEmpty,
            reason: 'zoom $zoom',
          );
        }
        for (final zoom in const [8.0, 20.0]) {
          expect(
            dotsOf(draw(painter(osm, zoom: zoom, brightness: brightness))),
            hasLength(2),
            reason: 'zoom $zoom',
          );
        }
      });

      test('a 6 pt dot inside a 1 pt outline, constant on screen', () {
        for (final zoom in const [8.0, 20.0]) {
          final dots = dotsOf(
            draw(painter(osm, zoom: zoom, brightness: brightness)),
          ).toList();
          final ring = dots[0].paint;
          final fill = dots[1].paint;
          expect(ring.strokeWidth * zoom, closeTo(8, 1e-6));
          expect(fill.strokeWidth * zoom, closeTo(6, 1e-6));
          expect(ring.strokeCap, StrokeCap.round);
          expect(
            ring.color.toARGB32(),
            palette.entranceOutline.toARGB32(),
            reason: 'outline',
          );
          expect(
            fill.color.toARGB32(),
            palette.entrance.toARGB32(),
            reason: 'fill',
          );
        }
      });

      test('the fade between 3x and 8x follows the schedule', () {
        final dots = dotsOf(
          draw(painter(osm, zoom: 5, brightness: brightness)),
        ).toList();
        expect(dots, hasLength(2));
        final want = opacityAt(MapSchedule.entrances, 5);
        expect(want, inExclusiveRange(0, 1));
        expect(near(dots[1].paint.color.a, want, 0.003), isTrue);
      });
    });
  }

  test('a door within 5 m of an RIT accessible entrance pin is dropped', () {
    final both = doors(const [OsmEntrance(door), OsmEntrance(nearby)]);
    final twin = accessibleEntrance(
      GeoCoordinate(door.longitude + 0.00003, door.latitude),
    );
    final plain = dotsOf(draw(painter(both, zoom: 8))).first;
    expect(plain.points, hasLength(2));
    final deduped = dotsOf(draw(painter(both, zoom: 8, extra: [twin]))).first;
    expect(deduped.points, hasLength(1));
  });

  test('in the all-places overview no pin is drawn, so the door stays', () {
    final twin = accessibleEntrance(
      GeoCoordinate(door.longitude + 0.00003, door.latitude),
    );
    final fountain = CampusMapFeature(
      id: 901,
      kind: 'water',
      kindName: 'Water fountains',
      name: 'Fountain',
      geometryType: 'Point',
      coordinates: const [
        [GeoCoordinate(-77.676, 43.0835)],
      ],
    );
    final dots = dotsOf(
      draw(
        painter(
          doors(const [OsmEntrance(door)]),
          zoom: 8,
          extra: [twin, fountain],
        ),
      ),
    );
    expect(dots.first.points, hasLength(1));
  });

  test('a door 20 m from the pin is kept', () {
    final far = accessibleEntrance(
      GeoCoordinate(door.longitude + 0.0003, door.latitude),
    );
    final dots = dotsOf(
      draw(painter(doors(const [OsmEntrance(door)]), zoom: 8, extra: [far])),
    );
    expect(dots.first.points, hasLength(1));
  });

  test('no OSM data draws no dots', () {
    expect(
      dotsOf(draw(painter(const OsmFeatures.empty(), zoom: 20))),
      isEmpty,
    );
  });

  group('names', () {
    setUpAll(loadGoldenFonts);

    List<PlacedLabel> plan(double zoom, OsmFeatures extras) {
      CampusMapPainter.resetGeometryCacheForTest();
      return painter(extras, zoom: zoom).labelPlanForTest(size);
    }

    test('only a named door is labelled, and only at 20x', () {
      for (final zoom in const [1.0, 3.0, 8.0, 19.0]) {
        expect(
          plan(zoom, osm).where((p) => p.candidate.cls == LabelClass.entrance),
          isEmpty,
          reason: 'zoom $zoom',
        );
      }
      final labels = plan(
        20,
        osm,
      ).where((p) => p.candidate.cls == LabelClass.entrance).toList();
      expect(labels, hasLength(1));
      expect(labels.single.candidate.text, 'Main entrance');
      expect(labels.single.candidate.cls.size, greaterThanOrEqualTo(11));
    });

    test('a door label never beats a building label', () {
      final without = plan(
        20,
        const OsmFeatures.empty(),
      ).where((p) => p.candidate.cls != LabelClass.entrance).toList();
      final withDoors = plan(
        20,
        osm,
      ).where((p) => p.candidate.cls != LabelClass.entrance).toList();
      expect(
        withDoors.map((p) => p.candidate.text).toList(),
        without.map((p) => p.candidate.text).toList(),
      );
    });
  });
}
