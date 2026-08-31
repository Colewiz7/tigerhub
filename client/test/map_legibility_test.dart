/// The map has to read as a map in both themes.
///
/// The map was hard to read at a glance, and the reason
/// was measurable rather than aesthetic: every colour in play sat within a
/// third of its neighbour, so buildings were faint wireframes on a field.
///
/// docs/notes.md 4 says colour is validated, never eyeballed. These are the numbers
/// that validation produced, pinned so a later palette change cannot quietly
/// undo it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_map.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(
        seedColor: const Color(0xFFF76902),
        brightness: brightness,
      );

  /// Below this a large block of colour stops reading as a distinct shape.
  const shapeFloor = 1.5;

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final s = scheme(brightness);
    final name = brightness.name;

    test('a building edge is visible against its own fill in $name', () {
      // The edge is what carries the building. outlineVariant measured 1.32
      // in both themes, which is why the outlines vanished.
      expect(
        contrast(s.outline, s.surfaceContainerHighest),
        greaterThan(3.0),
        reason: 'building outlines will not read in $name',
      );
    });

    test('a building edge is visible against the map background in $name', () {
      expect(
        contrast(s.outline, s.surfaceContainerLowest),
        greaterThan(shapeFloor),
        reason: 'buildings will not separate from the field in $name',
      );
    });

    test('the fill stays quieter than the edge in $name', () {
      // The fill is backdrop. If it ever out-contrasted the edge the map would
      // read as blocks rather than as outlined buildings.
      expect(
        contrast(s.surfaceContainerHighest, s.surfaceContainerLowest),
        lessThan(contrast(s.outline, s.surfaceContainerLowest)),
      );
    });
  }

  /// Composites a translucent paint over its background, the way the canvas
  /// does, so the measurement is of what actually lands on screen.
  Color over(Color fg, Color bg) => Color.fromARGB(
        255,
        (fg.a * fg.r * 255 + (1 - fg.a) * bg.r * 255).round(),
        (fg.a * fg.g * 255 + (1 - fg.a) * bg.g * 255).round(),
        (fg.a * fg.b * 255 + (1 - fg.a) * bg.b * 255).round(),
      );

  group('the three outline families separate', () {
    CampusMapFeature feature(String kindName) => CampusMapFeature(
          id: 1,
          kind: '_campus',
          kindName: kindName,
          name: kindName,
          geometryType: 'Polygon',
          coordinates: const [],
        );

    test('a parking apron is not a building', () {
      // 20 of the 191 outlines are parking, and lots are large. Painted as
      // buildings they read as the biggest structures on campus.
      for (final kind in [
        'Visitor Parking',
        'General Parking',
        'Reserved Parking',
        'Residential Parking',
      ]) {
        expect(mapFamily(feature(kind)), MapFamily.parking, reason: kind);
      }
    });

    test('vegetation is ground', () {
      for (final kind in [
        'Quads And Courtyards',
        'Pollinator Gardens',
        'Solar Fields',
        'Community Gardens',
      ]) {
        expect(mapFamily(feature(kind)), MapFamily.open, reason: kind);
      }
    });

    test('a building is classified by what kind of building it is', () {
      // Colour coding is only useful if the categories are actually told
      // apart. Residential is 106 of the 150 outlines, academic 30.
      expect(mapFamily(feature('Residential Building')), MapFamily.residential);
      expect(mapFamily(feature('Academic Building')), MapFamily.academic);
      expect(mapFamily(feature('Athletic Building')), MapFamily.athletic);
      for (final kind in ['Green Building', 'Restaurants', 'Campus structure']) {
        expect(mapFamily(feature(kind)), MapFamily.otherBuilt, reason: kind);
      }
    });

    test('every building kind still counts as built', () {
      for (final kind in [
        'Residential Building',
        'Academic Building',
        'Athletic Building',
        'Green Building',
        'Restaurants',
        'Campus structure',
      ]) {
        expect(mapFamily(feature(kind)).isBuilt, isTrue, reason: kind);
      }
      expect(MapFamily.parking.isBuilt, isFalse);
      expect(MapFamily.open.isBuilt, isFalse);
    });

    test('built draws last so it sits on top of ground', () {
      expect(MapFamily.open.rank, lessThan(MapFamily.parking.rank));
      expect(MapFamily.parking.rank, lessThan(MapFamily.residential.rank));
    });
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final s = scheme(brightness);
    final name = brightness.name;
    // What the outlines are actually drawn onto.
    final field = over(s.primary.withValues(alpha: 0.035), s.surface);

    test('parking reads, but stays under the buildings in $name', () {
      final edge = over(s.outline.withValues(alpha: 0.55), field);
      expect(contrast(edge, field), greaterThan(shapeFloor),
          reason: 'parking outlines will not read in $name');
      expect(
        contrast(edge, field),
        lessThan(contrast(s.outline, field)),
        reason: 'parking must never compete with a building in $name',
      );
    });

    test('open space reads as ground in $name', () {
      // The surface ramp could not do this: its best step measured 1.11 light
      // and 1.21 dark against the field, both under the floor.
      final fill = over(s.tertiary.withValues(alpha: 0.32), field);
      expect(contrast(fill, field), greaterThan(shapeFloor),
          reason: 'quads and gardens vanish in $name');
      expect(
        contrast(fill, field),
        lessThan(contrast(s.outline, field)),
        reason: 'ground must stay quieter than a building edge in $name',
      );
    });
  }

  test('the surface steps alone were never enough, in either theme', () {
    // Kept as the record of why this does not simply use two surface roles,
    // which is what the design spec originally asked for.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final s = scheme(brightness);
      expect(
        contrast(s.surfaceContainerHigh, s.surfaceContainerLowest),
        lessThan(shapeFloor),
        reason: 'if this ever passes, the spec pairing became viable and the '
            'edge-carries-the-shape workaround can be revisited',
      );
    }
  });
}
