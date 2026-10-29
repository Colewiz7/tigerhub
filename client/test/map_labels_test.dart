/// Label priorities, the 11 pt floor, collisions and the category glyphs.
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

import 'golden_harness.dart';
import 'map_repaint_test.dart' show polygon, schemeOf;

LabelCandidate cand(
  LabelClass cls, {
  Object? group,
  List<Rect>? positions,
  double w = 40,
}) => LabelCandidate(
  key: cls.name,
  cls: cls,
  size: Size(w, 14),
  positions: positions ?? [Rect.fromLTWH(10, 10, w, 14)],
  group: group,
);

void main() {
  group('planner', () {
    test('every class is at least 11 pt', () {
      for (final cls in LabelClass.values) {
        expect(cls.size, greaterThanOrEqualTo(mapLabelMinSize), reason: cls.name);
      }
    });

    test('collisions are won in the stated priority order', () {
      const order = [
        LabelClass.selected,
        LabelClass.activePin,
        LabelClass.fullName,
        LabelClass.abbreviation,
        LabelClass.street,
        LabelClass.entrance,
      ];
      expect(LabelClass.values, order);
      for (var winner = 0; winner < order.length; winner++) {
        final field = [for (final cls in order.skip(winner)) cand(cls)]
          ..shuffle();
        final placed = planLabels(field);
        expect(placed, hasLength(1));
        expect(placed.single.candidate.cls, order[winner]);
      }
    });

    test('a full name beats the abbreviation of the same building', () {
      final placed = planLabels([
        cand(LabelClass.abbreviation, group: 1),
        cand(LabelClass.fullName, group: 1, positions: [
          const Rect.fromLTWH(100, 100, 40, 14),
        ]),
      ]);
      expect(placed.map((p) => p.candidate.cls), [LabelClass.fullName]);
    });

    test('labels keep 3 pt apart', () {
      Rect at(double x) => Rect.fromLTWH(x, 0, 20, 14);
      bool both(double gap) => planLabels([
        cand(LabelClass.fullName, positions: [at(0)]),
        cand(LabelClass.abbreviation, positions: [at(20 + gap)]),
      ]).length == 2;
      expect(both(2), isFalse);
      expect(both(2.9), isFalse);
      expect(both(3.1), isTrue);
    });

    test('a later position is tried when the first is taken', () {
      final placed = planLabels([
        cand(LabelClass.fullName),
        cand(LabelClass.abbreviation, positions: [
          const Rect.fromLTWH(12, 12, 40, 14),
          const Rect.fromLTWH(200, 200, 40, 14),
        ]),
      ]);
      expect(placed.last.rect.left, 200);
    });

    test('a pin outranks every label, but the selected label stays', () {
      const pin = Rect.fromLTWH(10, 10, 30, 30);
      expect(
        planLabels([cand(LabelClass.fullName)], obstacles: const [pin]),
        isEmpty,
      );
      expect(
        planLabels([cand(LabelClass.selected)], obstacles: const [pin]),
        hasLength(1),
      );
    });

    test('glyphs show from 3x for building labels only', () {
      for (final cls in [
        LabelClass.selected,
        LabelClass.fullName,
        LabelClass.abbreviation,
      ]) {
        expect(mapGlyphShown(cls, 1), isFalse);
        expect(mapGlyphShown(cls, 2.99), isFalse);
        expect(mapGlyphShown(cls, 3), isTrue);
        expect(mapGlyphShown(cls, 20), isTrue);
      }
      for (final cls in [
        LabelClass.activePin,
        LabelClass.street,
        LabelClass.entrance,
      ]) {
        expect(mapGlyphShown(cls, 20), isFalse, reason: cls.name);
      }
    });
  });

  group('on the map', () {
    const size = Size(400, 400);
    final features = [
      polygon(1, 'Academic Building', lon: -77.680, building: 'ACA', size: 0.004),
      polygon(2, 'Residential Building', lon: -77.672, building: 'RES', size: 0.004),
      polygon(3, 'Athletic Building', lon: -77.680, lat: 43.091, building: 'ATH', size: 0.004),
      polygon(4, 'Restaurants', lon: -77.672, lat: 43.091, building: 'DIN', size: 0.004),
      polygon(5, 'Green Building', lon: -77.664, lat: 43.091, building: 'OTH', size: 0.004),
    ];

    CampusMapPainter painter(double zoom, {int? selectedId}) => CampusMapPainter(
      features: features,
      selectedId: selectedId,
      scheme: schemeOf(Brightness.light),
      zoom: zoom,
    );

    test('each category has its glyph from 3x and none below', () {
      expect(mapGlyph(MapFamily.academic), isNot(mapGlyph(MapFamily.residential)));
      final glyphs = {
        for (final family in [
          MapFamily.academic,
          MapFamily.residential,
          MapFamily.athletic,
          MapFamily.dining,
          MapFamily.otherBuilt,
        ])
          mapGlyph(family),
      };
      expect(glyphs, hasLength(5), reason: 'five categories, five glyphs');
      for (final zoom in const [1.0, 2.0, 2.99]) {
        final plan = painter(zoom).labelPlanForTest(size);
        expect(plan.where((p) => p.candidate.glyph), isEmpty, reason: '$zoom');
      }
      for (final zoom in const [3.0, 8.0, 20.0]) {
        final plan = painter(zoom).labelPlanForTest(size);
        expect(plan.where((p) => p.candidate.glyph), isNotEmpty, reason: '$zoom');
      }
    });

    test('a selected building is always named, even at 1x', () {
      final plan = painter(1, selectedId: 3).labelPlanForTest(size);
      final selected = plan.where((p) => p.candidate.cls == LabelClass.selected);
      expect(selected, hasLength(1));
      expect(selected.single.candidate.text, 'Polygon 3');
    });

    test('a building shows one name, and full names take over at 8x', () {
      for (final zoom in const [3.0, 8.0, 20.0]) {
        final plan = painter(zoom).labelPlanForTest(size);
        final keys = plan.map((p) => p.candidate.key).toList();
        expect(keys.toSet().length, keys.length, reason: 'zoom $zoom');
      }
      final plan = painter(8).labelPlanForTest(size);
      expect(
        plan.where((p) => p.candidate.cls == LabelClass.fullName),
        isNotEmpty,
      );
    });

    test('no two placed labels are closer than the padding', () {
      for (final zoom in const [1.0, 3.0, 8.0, 20.0]) {
        final plan = painter(zoom, selectedId: 2).labelPlanForTest(size);
        for (var i = 0; i < plan.length; i++) {
          for (var j = i + 1; j < plan.length; j++) {
            if (plan[i].candidate.cls == LabelClass.selected ||
                plan[j].candidate.cls == LabelClass.selected) {
              continue;
            }
            expect(
              plan[i].rect.inflate(mapLabelPadding).overlaps(plan[j].rect),
              isFalse,
              reason: 'zoom $zoom: ${plan[i].candidate.text} vs ${plan[j].candidate.text}',
            );
          }
        }
      }
    });
  });

  group('on the real campus fixture', () {
    final features = [
      for (final n in ['3', '11', '35'])
        ...parseCampusMapFeatures(
          File('test/fixtures/maps_category_$n.data').readAsStringSync(),
        ).map(CampusMapFeature.fromJson),
    ];
    const size = Size(390, 520);
    List<PlacedLabel> planAt(double zoom) => CampusMapPainter(
      features: features,
      selectedId: null,
      scheme: schemeOf(Brightness.light),
      zoom: zoom,
    ).labelPlanForTest(size);

    test('fewer, readable labels at 1x, more as the zoom opens up', () {
      CampusMapPainter.resetGeometryCacheForTest();
      final counts = [for (final z in const [1.0, 3.0, 8.0, 20.0]) planAt(z).length];
      // ignore: avoid_print
      print('labels at 1x/3x/8x/20x: $counts');
      expect(counts[0], lessThan(counts[1]));
      expect(counts[0], lessThanOrEqualTo(12));
      for (final z in const [1.0, 3.0, 8.0, 20.0]) {
        for (final p in planAt(z)) {
          expect(p.candidate.cls.size, greaterThanOrEqualTo(11));
        }
      }
    });

    testWidgets('1x names a few landmarks, with no glyphs', (tester) async {
      await loadGoldenFonts();
      CampusMapPainter.resetGeometryCacheForTest();
      final plan = planAt(1);
      CampusMapPainter.resetGeometryCacheForTest();
      expect(plan, isNotEmpty);
      expect(plan.length, lessThanOrEqualTo(6));
      expect(plan.where((p) => p.candidate.glyph), isEmpty);
    });

    test('RIT data alone gives no street or entrance labels: it has no names', () {
      for (final z in const [1.0, 8.0, 20.0]) {
        expect(
          planAt(z).where(
            (p) =>
                p.candidate.cls == LabelClass.street ||
                p.candidate.cls == LabelClass.entrance,
          ),
          isEmpty,
        );
      }
    });

    test('the OSM extract names doors at 20x and nothing below', () {
      final osm = OsmFeatures.parse(
        jsonDecode(File('assets/map/osm_features.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      List<PlacedLabel> doors(double zoom) {
        CampusMapPainter.resetGeometryCacheForTest();
        return CampusMapPainter(
          features: features,
          selectedId: null,
          scheme: schemeOf(Brightness.light),
          zoom: zoom,
          osm: osm,
        ).labelPlanForTest(size).where(
          (p) => p.candidate.cls == LabelClass.entrance,
        ).toList();
      }

      for (final z in const [1.0, 3.0, 8.0, 19.0]) {
        expect(doors(z), isEmpty, reason: 'zoom $z');
      }
      final labels = doors(20);
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(label.candidate.cls.size, greaterThanOrEqualTo(mapLabelMinSize));
        expect(label.candidate.text, isNot(contains('|')));
      }
    });
  });
}
