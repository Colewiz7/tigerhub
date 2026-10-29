/// The repainted map draws from the fixed palette and the zoom schedule.
///
/// The painter is run against a recording canvas, so these read the exact
/// paints it issues: colour, alpha and stroke width at each zoom.
library;

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_style.dart';

class Draw {
  Draw(this.kind, this.paint, this.depth, [this.path, this.points]);

  final Path? path;
  final List<Offset>? points;
  final String kind;
  final Paint paint;
  final int depth;

  bool get stroked => paint.style == PaintingStyle.stroke;
}

class RecordingCanvas implements Canvas {
  final draws = <Draw>[];
  var _depth = 0;

  @override
  void save() => _depth++;

  @override
  void restore() => _depth--;

  @override
  void drawRect(Rect rect, Paint paint) =>
      draws.add(Draw('rect', paint, _depth));

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      draws.add(Draw('rrect', paint, _depth));

  @override
  void drawPath(Path path, Paint paint) =>
      draws.add(Draw('path', paint, _depth, path));

  List<Path> get paths => [
    for (final d in draws)
      if (d.path != null && !d.stroked) d.path!,
  ];

  @override
  void drawPoints(PointMode mode, List<Offset> points, Paint paint) =>
      draws.add(Draw('points', paint, _depth, null, points));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      draws.add(Draw('line', paint, _depth));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

CampusMapFeature polygon(
  int id,
  String kindName, {
  double lon = -77.675,
  double lat = 43.085,
  String? building,
  double size = 0.0006,
}) => CampusMapFeature(
  id: id,
  kind: '_campus',
  kindName: kindName,
  name: 'Polygon $id',
  geometryType: 'Polygon',
  building: building,
  coordinates: [
    [
      GeoCoordinate(lon, lat),
      GeoCoordinate(lon + size, lat),
      GeoCoordinate(lon + size, lat + size),
      GeoCoordinate(lon, lat + size),
    ],
  ],
);

const paths = CampusPaths(
  foot: [
    [GeoCoordinate(-77.676, 43.084), GeoCoordinate(-77.670, 43.088)],
  ],
  road: [
    [GeoCoordinate(-77.676, 43.086), GeoCoordinate(-77.670, 43.086)],
  ],
);

final features = [
  polygon(1, 'Academic Building', lon: -77.678),
  polygon(2, 'Residential Building', lon: -77.676),
  polygon(3, 'Athletic Building', lon: -77.674),
  polygon(4, 'Restaurants', lon: -77.672),
  polygon(5, 'Green Building', lon: -77.670),
  polygon(6, 'General Parking', lat: 43.087),
  polygon(7, 'Quads And Courtyards', lat: 43.083),
];

ColorScheme schemeOf(Brightness brightness, [Color? seed]) =>
    ColorScheme.fromSeed(
      seedColor: seed ?? const Color(0xFFF76902),
      brightness: brightness,
    );

RecordingCanvas paint({
  required Brightness brightness,
  double zoom = 1,
  int? selectedId,
  Color? seed,
}) {
  final canvas = RecordingCanvas();
  CampusMapPainter(
    features: features,
    selectedId: selectedId,
    scheme: schemeOf(brightness, seed),
    zoom: zoom,
    paths: paths,
  ).paint(canvas, const Size(400, 400));
  return canvas;
}

bool near(double a, double b, [double eps = 0.004]) => (a - b).abs() < eps;

Iterable<Draw> withColor(RecordingCanvas canvas, Color color) =>
    canvas.draws.where(
      (d) =>
          d.paint.color.toARGB32() == color.toARGB32() ||
          (near(d.paint.color.r, color.r, 0.003) &&
              near(d.paint.color.g, color.g, 0.003) &&
              near(d.paint.color.b, color.b, 0.003)),
    );

void main() {
  const brightnesses = [Brightness.light, Brightness.dark];

  group('fills come from the fixed palette, not the wallpaper theme', () {
    for (final brightness in brightnesses) {
      final palette = MapPalette.of(brightness);
      for (final seed in const [Color(0xFFF76902), Color(0xFF2255CC)]) {
        test('${brightness.name}, seed ${seed.toARGB32().toRadixString(16)}', () {
          for (final entry in {
            MapFamily.academic: MapCategory.academic,
            MapFamily.residential: MapCategory.residential,
            MapFamily.athletic: MapCategory.athletic,
            MapFamily.dining: MapCategory.dining,
            MapFamily.otherBuilt: MapCategory.other,
          }.entries) {
            final paints = mapFamilyPaints(
              entry.key,
              schemeOf(brightness, seed),
            );
            expect(
              paints.fill!.color.toARGB32(),
              palette.fill(entry.value).toARGB32(),
              reason: entry.key.name,
            );
            expect(
              paints.edge!.color.toARGB32(),
              palette.buildingOutline.toARGB32(),
              reason: '${entry.key.name} edge',
            );
          }
          expect(
            mapFamilyPaints(MapFamily.open, schemeOf(brightness, seed))
                .fill!
                .color
                .toARGB32(),
            palette.grass.toARGB32(),
          );
        });
      }
    }
  });

  test('the dining family exists and is picked from the sub-category name', () {
    CampusMapFeature named(String kindName) => polygon(1, kindName);
    expect(mapFamily(named('Restaurants')), MapFamily.dining);
    expect(mapFamily(named('Dining Hall')), MapFamily.dining);
    expect(mapFamily(named('Academic Building')), MapFamily.academic);
    expect(mapFamily(named('Green Building')), MapFamily.otherBuilt);
    expect(mapFamily(named('Quads And Courtyards')), MapFamily.open);
  });

  group('zoom schedule', () {
    final scheme = schemeOf(Brightness.light);
    double fillAlpha(MapFamily family, double zoom) =>
        mapFamilyPaints(family, scheme, zoom: zoom).fill?.color.a ?? 0;

    test('parking is hidden at 1x and begins to appear at 3x', () {
      final hidden = mapFamilyPaints(MapFamily.parking, scheme, zoom: 1);
      expect(hidden.fill, isNull);
      expect(hidden.edge, isNull);
      expect(fillAlpha(MapFamily.parking, 1.5), greaterThan(0));
      expect(fillAlpha(MapFamily.parking, 3), closeTo(0.45, 0.001));
      expect(fillAlpha(MapFamily.parking, 8), closeTo(0.80, 0.001));
      expect(fillAlpha(MapFamily.parking, 20), closeTo(1.0, 0.001));
    });

    test('buildings and grass hit their anchors', () {
      expect(fillAlpha(MapFamily.academic, 1), closeTo(0.80, 0.001));
      expect(fillAlpha(MapFamily.academic, 3), closeTo(1.0, 0.001));
      expect(fillAlpha(MapFamily.otherBuilt, 1), closeTo(0.75, 0.001));
      expect(fillAlpha(MapFamily.open, 1), closeTo(0.55, 0.001));
      expect(fillAlpha(MapFamily.open, 3), closeTo(0.75, 0.001));
      expect(fillAlpha(MapFamily.open, 8), closeTo(1.0, 0.001));
    });

    test('the fade is smooth between anchors, not a pop', () {
      var previous = fillAlpha(MapFamily.parking, 1);
      for (var zoom = 1.1; zoom <= 20; zoom += 0.1) {
        final alpha = fillAlpha(MapFamily.parking, zoom);
        expect(alpha, greaterThanOrEqualTo(previous - 1e-9));
        expect(alpha - previous, lessThan(0.06), reason: 'at $zoom');
        previous = alpha;
      }
    });
  });

  for (final brightness in brightnesses) {
    final palette = MapPalette.of(brightness);

    group('painter, ${brightness.name}', () {
      test('the ground is the palette ground, fully opaque', () {
        final canvas = paint(brightness: brightness);
        final ground = canvas.draws.first;
        expect(ground.kind, 'rect');
        expect(ground.paint.color.toARGB32(), palette.ground.toARGB32());
      });

      test('building edges are 1 pt on screen at every zoom', () {
        for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
          final canvas = paint(brightness: brightness, zoom: zoom);
          final edges = withColor(
            canvas,
            _over(palette.buildingOutline, opacityAt(MapSchedule.building, zoom)),
          ).where((d) => d.stroked);
          expect(edges, isNotEmpty, reason: 'zoom $zoom');
          for (final edge in edges) {
            expect(edge.paint.strokeWidth * zoom, closeTo(1.0, 1e-5));
          }
        }
      });

      test('roads are casing plus core, 3.5 and 2.0 pt on screen', () {
        for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
          final canvas = paint(brightness: brightness, zoom: zoom);
          final widths = [
            for (final d in canvas.draws)
              if (d.stroked && d.paint.strokeCap == StrokeCap.round)
                d.paint.strokeWidth * zoom,
          ];
          expect(widths.where((w) => near(w, 3.5, 1e-6)), hasLength(1));
          expect(widths.where((w) => near(w, 2.0, 1e-6)), hasLength(1));
        }
      });

      test('road colours follow the palette and the schedule', () {
        final canvas = paint(brightness: brightness, zoom: 8);
        expect(
          withColor(canvas, palette.roadCasing).where((d) => d.stroked),
          isNotEmpty,
        );
        expect(
          withColor(canvas, palette.roadCore).where((d) => d.stroked),
          isNotEmpty,
        );
        final faint = paint(brightness: brightness, zoom: 1);
        final core = faint.draws.firstWhere(
          (d) => d.stroked && near(d.paint.strokeWidth, 2.0, 1e-6),
        );
        expect(core.paint.color.a, closeTo(0.45, 0.001));
      });

      test('footpaths are hidden at 1x, 1.25 pt from 3x', () {
        bool hasFoot(double zoom) => paint(brightness: brightness, zoom: zoom)
            .draws
            .any(
              (d) =>
                  d.stroked &&
                  near(d.paint.strokeWidth * zoom, 1.25, 1e-6) &&
                  d.paint.color.a > 0,
            );
        expect(hasFoot(1), isFalse);
        expect(hasFoot(3), isTrue);
        expect(hasFoot(8), isTrue);
        final foot = paint(brightness: brightness, zoom: 8).draws.firstWhere(
          (d) => d.stroked && near(d.paint.strokeWidth * 8, 1.25, 1e-6),
        );
        expect(foot.paint.color.toARGB32(), palette.footpath.toARGB32());
      });

      test('parking is not drawn at 1x and is drawn at 3x', () {
        bool hasParking(double zoom) {
          final canvas = paint(brightness: brightness, zoom: zoom);
          return canvas.draws.any(
            (d) =>
                d.stroked &&
                near(d.paint.strokeWidth * zoom, 0.75, 1e-6) &&
                d.paint.color.a > 0,
          );
        }

        expect(hasParking(1), isFalse);
        expect(hasParking(3), isTrue);
      });

      test('selection is a tonal overlay plus a solid 2.5 pt outline', () {
        for (final zoom in const [1.0, 8.0]) {
          final canvas = paint(brightness: brightness, zoom: zoom, selectedId: 2);
          final outline = canvas.draws.where(
            (d) =>
                d.stroked &&
                d.paint.color.toARGB32() == palette.selectedOutline.toARGB32(),
          );
          expect(outline, hasLength(1));
          expect(outline.single.paint.strokeWidth * zoom, closeTo(2.5, 1e-5));
          final overlay = canvas.draws.where(
            (d) =>
                !d.stroked &&
                d.paint.color.toARGB32() == palette.selectedOverlay.toARGB32(),
          );
          expect(overlay, hasLength(1));
        }
      });

      test('nothing is blurred, glowed or shadowed', () {
        final canvas = paint(brightness: brightness, zoom: 3, selectedId: 2);
        for (final d in canvas.draws) {
          expect(d.paint.maskFilter, isNull);
          expect(d.paint.imageFilter, isNull);
          expect(d.paint.colorFilter, isNull);
        }
      });
    });
  }

  testWidgets('the legend names dining', (tester) async {
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
    expect(find.text(MapFamily.dining.label), findsOneWidget);
  });
}

Color _over(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity);
