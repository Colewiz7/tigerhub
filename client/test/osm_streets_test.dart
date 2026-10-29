/// Street names: one upright label per street, from 8x, on its longest
/// straight run, losing every collision to a building or a pin.
library;

import 'dart:convert';
import 'dart:io';

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

const size = Size(390, 520);

List<PlacedLabel> streetsOf(List<PlacedLabel> plan) => [
  for (final p in plan)
    if (p.candidate.cls == LabelClass.street) p,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('longest straight run', () {
    test('a straight line is one run', () {
      final run = longestStraightRun([
        [const Offset(0, 0), const Offset(50, 0), const Offset(100, 0)],
      ])!;
      expect(run.length, 100);
      expect(run.mid, const Offset(50, 0));
    });

    test('an L picks the longer leg', () {
      final run = longestStraightRun([
        [
          const Offset(0, 0),
          const Offset(30, 0),
          const Offset(30, 90),
        ],
      ])!;
      expect(run.length, 90);
      expect(run.mid, const Offset(30, 45));
    });

    test('a gentle bend still counts as straight', () {
      final run = longestStraightRun([
        [const Offset(0, 0), const Offset(50, 5), const Offset(100, 0)],
      ])!;
      expect(run.length, greaterThan(100));
    });

    test('the longest way of several wins', () {
      final run = longestStraightRun([
        [const Offset(0, 0), const Offset(10, 0)],
        [const Offset(0, 5), const Offset(60, 5)],
      ])!;
      expect(run.length, 60);
    });

    test('nothing to label gives null', () {
      expect(longestStraightRun(const []), isNull);
      expect(longestStraightRun([const [Offset(1, 1)]]), isNull);
    });

    test('pointAlong walks by arc length', () {
      final line = [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)];
      expect(pointAlong(line, 0), const Offset(0, 0));
      expect(pointAlong(line, .75), const Offset(10, 5));
      expect(pointAlong(line, 1), const Offset(10, 10));
    });
  });

  group('on the real campus', () {
    setUpAll(loadGoldenFonts);

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

    List<PlacedLabel> plan(double zoom, {int? selectedId, OsmFeatures? extras}) {
      CampusMapPainter.resetGeometryCacheForTest();
      return CampusMapPainter(
        features: features,
        selectedId: selectedId,
        scheme: schemeOf(Brightness.light),
        zoom: zoom,
        osm: extras ?? osm,
      ).labelPlanForTest(size);
    }

    test('no street names below 8x', () {
      for (final z in const [1.0, 3.0, 7.9]) {
        expect(streetsOf(plan(z)), isEmpty, reason: 'zoom $z');
      }
    });

    test('streets are named from 8x', () {
      // ignore: avoid_print
      print('street labels at 8x/20x: ${streetsOf(plan(8)).length}/${streetsOf(plan(20)).length}');
      expect(streetsOf(plan(8)), isNotEmpty);
      expect(streetsOf(plan(20)).length, greaterThanOrEqualTo(streetsOf(plan(8)).length));
    });

    test('there is one label per street', () {
      for (final z in const [8.0, 20.0]) {
        final names = [for (final p in streetsOf(plan(z))) p.candidate.text];
        expect(names.toSet().length, names.length, reason: 'zoom $z');
      }
    });

    test('every street label is at least 11 pt', () {
      for (final p in streetsOf(plan(20))) {
        expect(p.candidate.cls.size, greaterThanOrEqualTo(mapLabelMinSize));
      }
    });

    test('a label never exceeds its run', () {
      final projection = CampusMapProjection(features, size);
      final runs = {
        for (final s in osm.street)
          s.name: longestStraightRun([
            for (final line in s.lines)
              [for (final c in line) projection.project(c)],
          ])!,
      };
      for (final z in const [8.0, 20.0]) {
        for (final p in streetsOf(plan(z))) {
          expect(
            p.rect.width,
            lessThanOrEqualTo(runs[p.candidate.text]!.length * z + 0.01),
            reason: '${p.candidate.text} at $z',
          );
        }
      }
    });

    test('streets lose to buildings and to a selected building', () {
      for (final z in const [8.0, 20.0]) {
        final withStreets = plan(z, selectedId: features.first.id);
        final without = plan(z, selectedId: features.first.id, extras: const OsmFeatures.empty());
        List<String> buildingTexts(List<PlacedLabel> labels) => [
          for (final p in labels)
            if (p.candidate.cls.index < LabelClass.street.index) p.candidate.text,
        ];
        expect(buildingTexts(withStreets), buildingTexts(without), reason: 'zoom $z');
      }
    });

    test('no street label crowds another label', () {
      for (final z in const [8.0, 20.0]) {
        final labels = plan(z);
        for (final street in streetsOf(labels)) {
          for (final other in labels) {
            if (identical(other, street)) continue;
            expect(
              street.rect.inflate(mapLabelPadding).overlaps(other.rect) &&
                  other.candidate.cls.index > street.candidate.cls.index,
              isFalse,
              reason: '${street.candidate.text} at $z',
            );
          }
        }
      }
    });

    test('no Judson or Tiger Stadium name can appear', () {
      for (final p in plan(20)) {
        final text = p.candidate.text.toLowerCase();
        expect(text, isNot(contains('judson')));
        expect(text, isNot(contains('tiger stadium')));
      }
    });
  });
}
