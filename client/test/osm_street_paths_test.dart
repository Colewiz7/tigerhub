/// Street names set along the street where it bends gently.
///
/// Anything harder, or a name longer than its run, falls back to the upright
/// label. Reverting the text-on-path commit leaves the upright labels alone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/osm_features.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_labels.dart';
import 'package:tigerhub/widgets/osm_geometry.dart';

import 'golden_harness.dart';
import 'map_repaint_test.dart' show schemeOf;

List<Offset> arc(double radius, double sweep, {int steps = 12}) => [
  for (var i = 0; i <= steps; i++)
    Offset(
      radius * math.sin(sweep * i / steps),
      radius * (1 - math.cos(sweep * i / steps)),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gentle run', () {
    test('a gentle arc is one run', () {
      final points = arc(200, 0.8);
      final run = longestGentleRun([points])!;
      expect(run.points.length, points.length);
    });

    test('a bend over 0.5 rad ends the run', () {
      final run = longestGentleRun([
        [const Offset(0, 0), const Offset(50, 0), const Offset(60, 50)],
      ])!;
      expect(run.points.length, 2);
    });

    test('a run turning more than 1 rad in all is cut', () {
      final points = arc(100, 2.4, steps: 12);
      final run = longestGentleRun([points])!;
      expect(run.points.length, lessThan(points.length));
      var turned = 0.0;
      for (var i = 2; i < run.points.length; i++) {
        final a = (run.points[i - 1] - run.points[i - 2]).direction;
        final b = (run.points[i] - run.points[i - 1]).direction;
        turned += (a - b).abs();
      }
      expect(turned, lessThanOrEqualTo(1.0));
    });

    test('a straight street is a gentle run of the same length', () {
      final line = [const Offset(0, 0), const Offset(100, 0)];
      expect(longestGentleRun([line])!.length, 100);
    });
  });

  group('layout along a run', () {
    const advances = [6.0, 7.0, 6.0, 7.0, 6.0];

    test('glyphs sit side by side, centred on the run', () {
      final glyphs = layoutAlongRun([const Offset(0, 0), const Offset(100, 0)], advances)!;
      expect(glyphs, hasLength(advances.length));
      final total = advances.fold<double>(0, (a, b) => a + b);
      final start = (100 - total) / 2;
      expect(glyphs.first.at.dx, closeTo(start + advances.first / 2, 1e-6));
      expect(glyphs.last.at.dx, closeTo(100 - start - advances.last / 2, 1e-6));
      for (var i = 1; i < glyphs.length; i++) {
        expect(
          glyphs[i].at.dx - glyphs[i - 1].at.dx,
          closeTo((advances[i] + advances[i - 1]) / 2, 1e-6),
        );
      }
      for (final glyph in glyphs) {
        expect(glyph.angle, closeTo(0, 1e-9));
      }
    });

    test('a run heading leftward is flipped so no glyph is upside down', () {
      final glyphs = layoutAlongRun([const Offset(100, 0), const Offset(0, 0)], advances)!;
      for (final glyph in glyphs) {
        expect(glyph.angle.abs(), lessThan(math.pi / 2));
      }
      for (var i = 1; i < glyphs.length; i++) {
        expect(glyphs[i].at.dx, greaterThan(glyphs[i - 1].at.dx));
      }
    });

    test('a rising and a falling run both read upright', () {
      for (final end in const [Offset(80, -60), Offset(-80, 60), Offset(-80, -60), Offset(80, 60)]) {
        final glyphs = layoutAlongRun([Offset.zero, end], advances)!;
        for (final glyph in glyphs) {
          expect(glyph.angle.abs(), lessThan(math.pi / 2), reason: '$end');
        }
      }
    });

    test('glyphs follow a bend, turning as the street does', () {
      final points = arc(120, 0.9);
      final glyphs = layoutAlongRun(points, const [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6])!;
      expect(glyphs.last.angle, greaterThan(glyphs.first.angle + 0.1));
      for (var i = 1; i < glyphs.length; i++) {
        expect(glyphs[i].angle, greaterThanOrEqualTo(glyphs[i - 1].angle - 1e-9));
      }
    });

    test('the label never exceeds its run', () {
      expect(
        layoutAlongRun([const Offset(0, 0), const Offset(32, 0)], advances),
        isNotNull,
      );
      expect(
        layoutAlongRun([const Offset(0, 0), const Offset(30, 0)], const [20.0, 20.0]),
        isNull,
      );
    });

    test('nothing to lay out gives null', () {
      expect(layoutAlongRun([const Offset(0, 0)], advances), isNull);
      expect(layoutAlongRun([const Offset(0, 0), const Offset(9, 0)], const []), isNull);
    });
  });

  group('on the real campus', () {
    setUpAll(loadGoldenFonts);

    const size = Size(390, 520);
    final features = [
      for (final n in ['3', '11', '35'])
        ...parseCampusMapFeatures(
          File('test/fixtures/maps_category_$n.data').readAsStringSync(),
        ).map(CampusMapFeature.fromJson),
    ];
    final osm = OsmFeatures.parse(
      jsonDecode(File('assets/map/osm_features.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    List<PlacedLabel> streets(double zoom, {OsmFeatures? extras}) {
      CampusMapPainter.resetGeometryCacheForTest();
      return [
        for (final p in CampusMapPainter(
          features: features,
          selectedId: null,
          scheme: schemeOf(Brightness.light),
          zoom: zoom,
          osm: extras ?? osm,
        ).labelPlanForTest(size))
          if (p.candidate.cls == LabelClass.street) p,
      ];
    }

    test('streets are set along their run where they bend gently', () {
      for (final z in const [8.0, 20.0]) {
        final plan = streets(z);
        final onPath = [for (final p in plan) if (p.candidate.payload is PathLabel) p];
        // ignore: avoid_print
        print('zoom $z: ${onPath.length} on a path of ${plan.length} streets');
        expect(onPath, isNotEmpty, reason: 'zoom $z');
        for (final p in onPath) {
          final label = p.candidate.payload! as PathLabel;
          expect(label.glyphs.length, p.candidate.text.characters.length);
          expect(label.inks.length, label.glyphs.length);
          for (final glyph in label.glyphs) {
            expect(glyph.angle.abs(), lessThan(1.75), reason: p.candidate.text);
          }
        }
      }
    });

    test('a path label stays on its run', () {
      final projection = CampusMapProjection(features, size);
      final runs = {
        for (final s in osm.street)
          s.name: longestGentleRun([
            for (final line in s.lines)
              [for (final c in line) projection.project(c)],
          ])!,
      };
      for (final z in const [8.0, 20.0]) {
        for (final p in streets(z)) {
          final label = p.candidate.payload;
          if (label is! PathLabel) continue;
          final span = (label.glyphs.last.at - label.glyphs.first.at).distance;
          expect(
            span,
            lessThanOrEqualTo(runs[p.candidate.text]!.length * z + 0.01),
            reason: '${p.candidate.text} at $z',
          );
        }
      }
    });

    test('there is still one label per street', () {
      for (final z in const [8.0, 20.0]) {
        final names = [for (final p in streets(z)) p.candidate.text];
        expect(names.toSet().length, names.length);
      }
    });

    test('a name longer than any run gets no label at all', () {
      final extras = OsmFeatures(
        street: [
          OsmStreet('A very long street name that cannot fit anywhere', const [
            [GeoCoordinate(-77.675, 43.085), GeoCoordinate(-77.67495, 43.08501)],
          ]),
        ],
      );
      expect(streets(8, extras: extras), isEmpty);
    });

    test('a street name is never smaller than 11 pt', () {
      for (final p in streets(20)) {
        expect(p.candidate.cls.size, greaterThanOrEqualTo(mapLabelMinSize));
      }
    });
  });
}
