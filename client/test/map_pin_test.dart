/// The scalloped pin: seven real arcs, screen-constant, readable counts.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_pin.dart';
import 'package:tigerhub/widgets/map_style.dart';

import 'golden_harness.dart';
import 'map_legibility_test.dart' show contrast;
import 'map_repaint_test.dart' show RecordingCanvas, polygon, schemeOf;

CampusMapFeature eventPoint(int id, String kind, double lon, double lat) =>
    CampusMapFeature(
      id: id,
      kind: kind,
      kindName: 'Events',
      name: 'Event $id',
      geometryType: 'Point',
      coordinates: [
        [GeoCoordinate(lon, lat)],
      ],
    );

/// Path.getBounds includes arc control points, so measure the drawn outline.
double _drawnWidth(Path path) {
  final metric = path.computeMetrics().single;
  var low = double.infinity;
  var high = -double.infinity;
  for (var i = 0; i < 720; i++) {
    final x = metric.getTangentForOffset(metric.length * i / 720)!.position.dx;
    low = math.min(low, x);
    high = math.max(high, x);
  }
  return high - low;
}

final backdrop =polygon(1, 'Academic Building', size: 0.004);

void main() {
  const center = Offset(100, 100);
  const radius = 40.0;

  group('scallop geometry', () {
    test('has exactly seven lobes', () {
      expect(scallopLobes, 7);
      expect(scallopArcs(center, radius), hasLength(7));
    });

    test('the outline is made of those arcs, not straight segments', () {
      final arcs = scallopArcs(center, radius);
      final path = scallopPath(center, radius);
      final metric = path.computeMetrics().single;
      var samples = 0;
      for (var d = 0.0; d < metric.length; d += metric.length / 700) {
        final at = metric.getTangentForOffset(d)!.position;
        final off = arcs
            .map((a) => ((at - a.center).distance - a.radius).abs())
            .reduce(math.min);
        expect(off, lessThan(radius * 0.004), reason: 'sample $samples');
        samples++;
      }
    });

    test('the radial profile has seven peaks at the full radius', () {
      final metric = scallopPath(center, radius).computeMetrics().single;
      const n = 1400;
      final profile = [
        for (var i = 0; i < n; i++)
          (metric.getTangentForOffset(metric.length * i / n)!.position - center)
              .distance,
      ];
      var peaks = 0;
      for (var i = 0; i < n; i++) {
        final before = profile[(i - 1) % n];
        final after = profile[(i + 1) % n];
        if (profile[i] > before && profile[i] >= after && profile[i] > radius * 0.97) {
          peaks++;
        }
      }
      expect(peaks, 7);
      expect(profile.reduce(math.max), closeTo(radius, radius * 0.003));
      expect(profile.reduce(math.min), closeTo(radius * 0.93, radius * 0.01));
    });

    test('a lobe is round between its notches', () {
      // a straight-edged star sits at the notch-chord midpoint; an arc
      // bulges well past it
      final arcs = scallopArcs(center, radius);
      final a = arcs.first;
      final chordMid = (a.from + a.to) / 2;
      final bulge = (a.center - chordMid).distance;
      expect(a.radius - bulge, greaterThan(radius * 0.1));
    });
  });

  group('pins on the map', () {
    List<Path> pinShapes(double zoom, {int? selectedId}) {
      final canvas = RecordingCanvas();
      CampusMapPainter(
        features: [
          backdrop,
          eventPoint(2, '_event:3', -77.675, 43.087),
        ],
        selectedId: selectedId,
        scheme: schemeOf(Brightness.light),
        zoom: zoom,
      ).paint(canvas, const Size(400, 400));
      return canvas.paths;
    }

    test('a count pin is 30 pt across from 1x to 20x', () {
      for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
        final shape = pinShapes(zoom).last;
        expect(
          _drawnWidth(shape) * zoom,
          closeTo(30, 1.5),
          reason: 'zoom $zoom',
        );
      }
    });

    test('a selected pin is 30 pt with a solid outline', () {
      final canvas = RecordingCanvas();
      CampusMapPainter(
        features: [backdrop, eventPoint(2, '_event:3', -77.675, 43.087)],
        selectedId: 2,
        scheme: schemeOf(Brightness.light),
        zoom: 8,
      ).paint(canvas, const Size(400, 400));
      final ring = canvas.draws.lastWhere((d) => d.stroked);
      expect(ring.paint.strokeWidth * 8, closeTo(2, 1e-5));
      expect(
        ring.paint.color.toARGB32(),
        MapPalette.light.selectedOutline.toARGB32(),
      );
      expect(ring.paint.maskFilter, isNull);
    });
  });

  // one test, one async block: a second toImage in the same test process
  // deadlocks under runAsync
  testWidgets('the count is readable on the badge that is actually drawn', (
    tester,
  ) async {
    await loadGoldenFonts();
    const size = Size(400, 400);
    const ratio = 4.0;
    final cases = [
      for (final brightness in Brightness.values)
        for (final kind in const ['_event:7', '_event:214'])
          (brightness: brightness, kind: kind),
    ];
    final renders = (await tester.runAsync(() async {
      final out = <ByteData>[];
      for (final c in cases) {
        final features = [backdrop, eventPoint(2, c.kind, -77.673, 43.087)];
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        CampusMapPainter(
          features: features,
          selectedId: null,
          scheme: schemeOf(c.brightness),
          zoom: 1,
        ).paint(canvas, size);
        final image = await recorder.endRecording().toImage(
          (size.width * ratio).round(),
          (size.height * ratio).round(),
        );
        out.add((await image.toByteData(format: ui.ImageByteFormat.rawRgba))!);
        image.dispose();
      }
      return out;
    }))!;
    for (var n = 0; n < cases.length; n++) {
      final brightness = cases[n].brightness;
      final bytes = renders[n];
      final palette = MapPalette.of(brightness);
      final features = [
        backdrop,
        eventPoint(2, cases[n].kind, -77.673, 43.087),
      ];
      final spot = CampusMapProjection(features, size).project(
        features.last.anchor!,
      );
      {
        {
          final width = (size.width * ratio).round();
          Color pixel(double dx, double dy) {
            final x = ((spot.dx + dx) * ratio).round();
            final y = ((spot.dy + dy) * ratio).round();
            final i = (y * width + x) * 4;
            return Color.fromARGB(
              bytes.getUint8(i + 3),
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
            );
          }

          // below the text row, still inside the lobes
          final badge = pixel(0, 9.5);
          expect(badge.toARGB32(), palette.clusterBadge.toARGB32());

          // the pixel furthest from the badge across the count's own box
          var worst = badge;
          var best = 1.0;
          for (var dx = -16.0; dx <= 16; dx += 0.25) {
            for (var dy = -5.0; dy <= 5; dy += 0.25) {
              final p = pixel(dx, dy);
              final c = contrast(p, badge);
              if (c > best) {
                best = c;
                worst = p;
              }
            }
          }
          final why = '${brightness.name} ${cases[n].kind}';
          expect(
            worst.toARGB32(),
            palette.clusterBadgeText.toARGB32(),
            reason: 'fully covered text pixels carry the text colour, $why',
          );
          expect(best, greaterThanOrEqualTo(4.5), reason: why);
        }
      }
    }
  });

  test('count text holds the 11 pt floor', () {
    expect(mapCountSize, greaterThanOrEqualTo(11));
  });
}
