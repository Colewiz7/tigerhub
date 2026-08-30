/// The map has to read as a map in both themes.
///
/// Cole: "it's currently hard to distinguish the map". It was, and the reason
/// was measurable rather than aesthetic: every colour in play sat within a
/// third of its neighbour, so buildings were faint wireframes on a field.
///
/// CLAUDE.md 4 says colour is validated, never eyeballed. These are the numbers
/// that validation produced, pinned so a later palette change cannot quietly
/// undo it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
