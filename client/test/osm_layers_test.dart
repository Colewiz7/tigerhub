/// OpenStreetMap water, green space and pitches on the map.
///
/// The painter runs against a recording canvas, so these read the exact paints
/// it issues, the same way map_repaint_test does for RIT's own shapes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/osm_features.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_style.dart';
import 'package:tigerhub/widgets/osm_geometry.dart';

import 'map_repaint_test.dart'
    show RecordingCanvas, Draw, features, near, schemeOf;

List<GeoCoordinate> box(
  double lon,
  double lat,
  double size, {
  bool flip = false,
}) {
  final ring = [
    GeoCoordinate(lon, lat),
    GeoCoordinate(lon + size, lat),
    GeoCoordinate(lon + size, lat + size),
    GeoCoordinate(lon, lat + size),
  ];
  return flip ? ring.reversed.toList() : ring;
}

final osm = OsmFeatures(
  water: [box(-77.676, 43.0835, 0.001)],
  waterway: const [
    [GeoCoordinate(-77.677, 43.0832), GeoCoordinate(-77.672, 43.0838)],
  ],
  park: [box(-77.674, 43.0845, 0.001)],
  pitch: [box(-77.671, 43.0845, 0.0006)],
);

RecordingCanvas paintWith(
  OsmFeatures extras, {
  required Brightness brightness,
  double zoom = 1,
}) {
  final canvas = RecordingCanvas();
  CampusMapPainter(
    features: features,
    selectedId: null,
    scheme: schemeOf(brightness),
    zoom: zoom,
    osm: extras,
  ).paint(canvas, const Size(400, 400));
  return canvas;
}

bool hasColor(Draw d, Color color, double opacity) {
  final want = color.withValues(alpha: color.a * opacity);
  return near(d.paint.color.r, want.r, 0.003) &&
      near(d.paint.color.g, want.g, 0.003) &&
      near(d.paint.color.b, want.b, 0.003) &&
      near(d.paint.color.a, want.a, 0.003);
}

void main() {
  for (final brightness in const [Brightness.light, Brightness.dark]) {
    final palette = MapPalette.of(brightness);

    group('OSM ground, ${brightness.name}', () {
      test('water uses the palette and the water schedule at every zoom', () {
        for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
          final canvas = paintWith(osm, brightness: brightness, zoom: zoom);
          final opacity = opacityAt(MapSchedule.water, zoom);
          expect(
            canvas.draws.where(
              (d) => !d.stroked && hasColor(d, palette.water, opacity),
            ),
            hasLength(1),
            reason: 'fill at $zoom',
          );
          final outline = canvas.draws.where(
            (d) => d.stroked && hasColor(d, palette.waterOutline, opacity),
          );
          expect(outline, isNotEmpty, reason: 'outline at $zoom');
        }
      });

      test('the water outline is 0.75 pt on screen', () {
        for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
          final canvas = paintWith(osm, brightness: brightness, zoom: zoom);
          final outline = canvas.draws.firstWhere(
            (d) =>
                d.stroked &&
                hasColor(
                  d,
                  palette.waterOutline,
                  opacityAt(MapSchedule.water, zoom),
                ) &&
                near(d.paint.strokeWidth * zoom, 0.75, 1e-6),
          );
          expect(outline.path, isNotNull);
        }
      });

      test('green and pitches reuse the grass fill with no new colour', () {
        for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
          final empty = paintWith(
            const OsmFeatures.empty(),
            brightness: brightness,
            zoom: zoom,
          );
          final withOsm = paintWith(osm, brightness: brightness, zoom: zoom);
          final opacity = opacityAt(MapSchedule.grass, zoom);
          int grass(RecordingCanvas c) => c.draws
              .where((d) => !d.stroked && hasColor(d, palette.grass, opacity))
              .length;
          expect(grass(withOsm), grass(empty) + 1, reason: 'zoom $zoom');
        }
      });

      test('a pitch edge is the parking stroke on the grass schedule', () {
        for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
          final opacity = opacityAt(MapSchedule.grass, zoom);
          int edges(RecordingCanvas c) => c.draws
              .where(
                (d) =>
                    d.stroked &&
                    hasColor(d, palette.parkingStroke, opacity) &&
                    near(d.paint.strokeWidth * zoom, 0.75, 1e-6),
              )
              .length;
          final plain = paintWith(
            const OsmFeatures.empty(),
            brightness: brightness,
            zoom: zoom,
          );
          final withOsm = paintWith(osm, brightness: brightness, zoom: zoom);
          expect(edges(withOsm), edges(plain) + 1, reason: 'zoom $zoom');
        }
      });

      test('water and green sit under RIT shapes and the paths', () {
        final canvas = paintWith(osm, brightness: brightness, zoom: 8);
        int first(bool Function(Draw) test) => canvas.draws.indexWhere(test);
        final water = first((d) => !d.stroked && hasColor(d, palette.water, 1));
        final green = first((d) => !d.stroked && hasColor(d, palette.grass, 1));
        final road = first(
          (d) => d.stroked && hasColor(d, palette.roadCasing, 1),
        );
        final building = first(
          (d) => !d.stroked && hasColor(d, palette.academic, 1),
        );
        final ground = first((d) => d.kind == 'rect');
        expect(ground, lessThan(water));
        expect(water, lessThan(green + 1));
        if (road >= 0) expect(green, lessThan(road));
        expect(green, lessThan(building));
      });

      test('nothing OSM is blurred, glowed or shadowed', () {
        final canvas = paintWith(osm, brightness: brightness, zoom: 3);
        for (final d in canvas.draws) {
          expect(d.paint.maskFilter, isNull);
          expect(d.paint.imageFilter, isNull);
          expect(d.paint.colorFilter, isNull);
        }
      });

      test('with no OSM data the map draws exactly what it drew before', () {
        final plain = paintWith(
          const OsmFeatures.empty(),
          brightness: brightness,
        );
        final withOsm = paintWith(osm, brightness: brightness);
        expect(withOsm.draws.length, greaterThan(plain.draws.length));
        expect(
          plain.draws.every((d) => !hasColor(d, palette.water, 0.7)),
          isTrue,
        );
      });
    });
  }

  group('ring winding', () {
    test('opposite-winding overlaps still fill', () {
      final a = [
        const Offset(0, 0),
        const Offset(20, 0),
        const Offset(20, 20),
        const Offset(0, 20),
      ];
      final b = [for (final p in a.reversed) p + const Offset(5, 5)];
      final path = ringsPath([a, b]);
      expect(path.contains(const Offset(10, 10)), isTrue);
      expect(path.contains(const Offset(24, 24)), isTrue);
      // the same pair in one path, unnormalised, cancels where they overlap
      final raw = Path()
        ..addPolygon(a, true)
        ..addPolygon(b, true);
      expect(raw.contains(const Offset(10, 10)), isFalse);
    });

    test('signed area flips with direction', () {
      final a = [
        const Offset(0, 0),
        const Offset(4, 0),
        const Offset(4, 4),
        const Offset(0, 4),
      ];
      expect(signedArea(a), 16);
      expect(signedArea(a.reversed.toList()), -16);
    });

    test('rings under three points and lines under two are skipped', () {
      expect(
        ringsPath([
          const [Offset(0, 0), Offset(1, 1)],
        ]).getBounds(),
        Rect.zero,
      );
      expect(
        linesPath([
          const [Offset(0, 0)],
        ]).getBounds(),
        Rect.zero,
      );
    });
  });

  testWidgets('the legend names water and credits OpenStreetMap at 11 pt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: schemeOf(Brightness.light)),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CampusMapView(
              result: Result(
                value: Collection(data: features, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Water'), findsOneWidget);
    final credit = find.text('(c) OpenStreetMap contributors');
    expect(credit, findsOneWidget);
    expect(
      tester.widget<Text>(credit).style!.fontSize,
      greaterThanOrEqualTo(11),
    );
  });
}
