/// The fixed map palette meets its contrast and schedule contracts.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/map_style.dart';

import 'map_legibility_test.dart' show contrast;

const _named = {'light': MapPalette.light, 'dark': MapPalette.dark};

Color _over(Color fg, Color bg) => Color.fromARGB(
  255,
  (fg.a * fg.r * 255 + (1 - fg.a) * bg.r * 255).round(),
  (fg.a * fg.g * 255 + (1 - fg.a) * bg.g * 255).round(),
  (fg.a * fg.b * 255 + (1 - fg.a) * bg.b * 255).round(),
);

// rec 601 luma on the srgb values, what a grayscale screenshot does
double _gray(Color c) => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

void main() {
  for (final entry in _named.entries) {
    final name = entry.key;
    final p = entry.value;
    final surfaces = {
      'ground': p.ground,
      'grass': p.grass,
      'water': p.water,
      'parking': p.parking,
      for (final c in MapCategory.values) c.name: p.fill(c),
    };

    test('primary text clears 4.5 on every fill in $name', () {
      for (final s in surfaces.entries) {
        expect(
          contrast(p.labelInk, s.value),
          greaterThanOrEqualTo(4.5),
          reason: '$name ${s.key}',
        );
      }
    });

    test('primary text stays above 11 on every fill in $name', () {
      for (final s in surfaces.entries) {
        expect(
          contrast(p.labelInk, s.value),
          greaterThan(11),
          reason: '$name ${s.key}',
        );
      }
    });

    test('secondary text clears its floor on ground in $name', () {
      final floor = name == 'light' ? 5.5 : 9.0;
      expect(contrast(p.labelSecondary, p.ground), greaterThanOrEqualTo(floor));
    });

    test('secondary text clears 4.5 on every fill in $name', () {
      for (final s in surfaces.entries) {
        expect(
          contrast(p.labelSecondary, s.value),
          greaterThanOrEqualTo(4.5),
          reason: '$name ${s.key}',
        );
      }
    });

    test('label halo is the ground colour in $name', () {
      expect(p.labelHalo, p.ground);
    });

    test('selected outline reads on every category fill in $name', () {
      for (final c in MapCategory.values) {
        expect(
          contrast(p.selectedOutline, p.fill(c)),
          greaterThanOrEqualTo(3),
          reason: '$name ${c.name}',
        );
        final tinted = _over(p.selectedOverlay, p.fill(c));
        expect(
          contrast(p.selectedOutline, tinted),
          greaterThanOrEqualTo(3),
          reason: '$name ${c.name} tinted',
        );
      }
    });

    test(
      'roads, footpaths and building outlines separate from ground in $name',
      () {
        expect(
          contrast(p.roadCore, p.ground),
          greaterThanOrEqualTo(1.5),
          reason: 'road core',
        );
        expect(
          contrast(p.footpath, p.ground),
          greaterThanOrEqualTo(1.5),
          reason: 'footpath',
        );
        expect(
          contrast(p.buildingOutline, p.ground),
          greaterThanOrEqualTo(1.5),
          reason: 'building outline',
        );
      },
    );

    test('quieter strokes still read at all in $name', () {
      // parking and water strokes are 0.75pt and meant to stay faint
      expect(
        contrast(p.parkingStroke, p.ground),
        greaterThanOrEqualTo(1.3),
        reason: 'parking stroke',
      );
      expect(
        contrast(p.waterOutline, p.ground),
        greaterThanOrEqualTo(1.3),
        reason: 'water outline',
      );
    });

    test('event pin count clears 4.5 on the rendered badge in $name', () {
      expect(
        contrast(p.clusterBadgeText, p.clusterBadge),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('entrances read against ground in $name', () {
      expect(contrast(p.entrance, p.ground), greaterThanOrEqualTo(4.0));
    });
  }

  test('accessible orange clears 4.5 on white', () {
    expect(
      contrast(const Color(0xFFC75300), const Color(0xFFFFFFFF)),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark accent clears 4.5 on dark ground', () {
    expect(
      contrast(const Color(0xFFFF9A4C), const Color(0xFF151412)),
      greaterThanOrEqualTo(4.5),
    );
  });

  group('research doc ratios match computed within 0.1', () {
    const l = MapPalette.light;
    const d = MapPalette.dark;
    final stated = <String, (Color, Color, double)>{
      'light ground 13.0': (l.labelInk, l.ground, 13.0),
      'light grass 12.2': (l.labelInk, l.grass, 12.2),
      'light water 11.9': (l.labelInk, l.water, 11.9),
      'light academic 11.2': (l.labelInk, l.academic, 11.2),
      'light residential 11.7': (l.labelInk, l.residential, 11.7),
      'light athletic 11.9': (l.labelInk, l.athletic, 11.9),
      'light dining 11.7': (l.labelInk, l.dining, 11.7),
      'light other 11.6': (l.labelInk, l.other, 11.6),
      'light parking 11.8': (l.labelInk, l.parking, 11.8),
      'dark ground 16.2': (d.labelInk, d.ground, 16.2),
      'dark grass 14.2': (d.labelInk, d.grass, 14.2),
      'dark water 14.0': (d.labelInk, d.water, 14.0),
      'dark academic 13.0': (d.labelInk, d.academic, 13.0),
      'dark residential 13.0': (d.labelInk, d.residential, 13.0),
      'dark athletic 13.0': (d.labelInk, d.athletic, 13.0),
      'dark dining 12.8': (d.labelInk, d.dining, 12.8),
      'dark other 13.8': (d.labelInk, d.other, 13.8),
      'dark parking 14.9': (d.labelInk, d.parking, 14.9),
      'light badge 4.5': (l.clusterBadgeText, l.clusterBadge, 4.5),
      'dark badge 8.8': (d.clusterBadgeText, d.clusterBadge, 8.8),
    };
    for (final s in stated.entries) {
      test(s.key, () {
        final (a, b, want) = s.value;
        expect((contrast(a, b) - want).abs(), lessThan(0.1));
      });
    }
  });

  group('grayscale gate', () {
    // fills alone never separate the categories in gray, the widest gap is
    // 5.8 of 255, so each category must carry its own glyph in the footprint
    const grayFloor = 12.0;
    const glyphCue = {
      MapCategory.academic: 'mortarboard',
      MapCategory.residential: 'house',
      MapCategory.athletic: 'ball',
      MapCategory.dining: 'fork',
      MapCategory.other: 'dot',
    };

    test('every category has its own glyph', () {
      expect(glyphCue.values.toSet().length, MapCategory.values.length);
    });

    for (final entry in _named.entries) {
      final p = entry.value;
      final cats = MapCategory.values;
      for (var i = 0; i < cats.length; i++) {
        for (var j = i + 1; j < cats.length; j++) {
          test(
            '${entry.key} ${cats[i].name} vs ${cats[j].name} is told apart in gray',
            () {
              final gap =
                  (_gray(p.fill(cats[i])) - _gray(p.fill(cats[j]))).abs() * 255;
              final byFill = gap >= grayFloor;
              final byGlyph = glyphCue[cats[i]] != glyphCue[cats[j]];
              expect(byFill || byGlyph, isTrue);
            },
          );
        }
      }
    }
  });

  group('opacity schedule', () {
    const schedules = {
      'ground': MapSchedule.ground,
      'grass': MapSchedule.grass,
      'water': MapSchedule.water,
      'building': MapSchedule.building,
      'otherBuilding': MapSchedule.otherBuilding,
      'parking': MapSchedule.parking,
      'roads': MapSchedule.roads,
      'footpaths': MapSchedule.footpaths,
      'entrances': MapSchedule.entrances,
      'selected': MapSchedule.selected,
    };

    test('hits every anchor exactly', () {
      for (final s in schedules.entries) {
        for (var i = 0; i < mapZoomStops.length; i++) {
          expect(
            opacityAt(s.value, mapZoomStops[i]),
            closeTo(s.value[i], 1e-9),
            reason: '${s.key} @${mapZoomStops[i]}',
          );
        }
      }
    });

    test('clamps outside the anchor range', () {
      expect(opacityAt(MapSchedule.parking, 0.5), 0.0);
      expect(opacityAt(MapSchedule.parking, 40), 1.0);
    });

    test('parking is hidden at 1x and shows by 3x', () {
      expect(opacityAt(MapSchedule.parking, 1), 0);
      expect(opacityAt(MapSchedule.parking, 3), closeTo(0.45, 1e-9));
    });

    test('interpolates on a log scale', () {
      // geometric midpoint of 1 and 3 is half way
      expect(opacityAt(MapSchedule.roads, math.sqrt(3)), closeTo(0.575, 1e-9));
      // linear midpoint would be 0.5875 on the first leg
      expect(opacityAt(MapSchedule.roads, 2), isNot(closeTo(0.5875, 1e-3)));
    });

    test('never decreases as zoom rises', () {
      for (final s in schedules.entries) {
        var last = -1.0;
        for (var z = 1.0; z <= 20.0; z += 0.05) {
          final v = opacityAt(s.value, z);
          expect(v, greaterThanOrEqualTo(last - 1e-12), reason: '${s.key} @$z');
          expect(v, inInclusiveRange(0.0, 1.0));
          last = v;
        }
      }
    });
  });
}
