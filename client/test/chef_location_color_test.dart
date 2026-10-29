/// The colour a chef row gives its location name.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/chef_location_color.dart';
import 'package:tigerhub/models/api_models.dart';

double _contrast(Color a, Color b) {
  final hi = math.max(a.computeLuminance(), b.computeLuminance());
  final lo = math.min(a.computeLuminance(), b.computeLuminance());
  return (hi + 0.05) / (lo + 0.05);
}

double _apart(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: const Color(0xFFF76902),
  brightness: brightness,
);

// every surface step a card or a row inside one is drawn on
List<Color> _surfaces(ColorScheme s) => [
  s.surface,
  s.surfaceContainerLowest,
  s.surfaceContainerLow,
  s.surfaceContainer,
  s.surfaceContainerHigh,
  s.surfaceContainerHighest,
];

void main() {
  for (final brightness in Brightness.values) {
    final scheme = _scheme(brightness);
    Color pick(ChefLocationColor c) => brightness == Brightness.dark ? c.dark : c.light;

    test('every location colour is at least 4.5:1 on every card surface, ${brightness.name}', () {
      for (final entry in chefLocationColors.entries) {
        for (final surface in _surfaces(scheme)) {
          expect(
            _contrast(pick(entry.value), surface),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.value.name} (${entry.key}) on $surface',
          );
        }
      }
    });

    test('the fallback colour is at least 4.5:1 on every card surface, ${brightness.name}', () {
      for (final surface in _surfaces(scheme)) {
        expect(_contrast(scheme.onSurfaceVariant, surface), greaterThanOrEqualTo(4.5));
      }
    });

    test('no two locations share a colour, ${brightness.name}', () {
      final entries = chefLocationColors.values.toList();
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          expect(
            _apart(pick(entries[i]), pick(entries[j])),
            greaterThan(60),
            reason: '${entries[i].name} and ${entries[j].name}',
          );
        }
      }
    });
  }

  group('which colour a chef gets', () {
    final scheme = _scheme(Brightness.light);
    MenuItem chef(String place, {int? id}) =>
        MenuItem(id: 1, name: 'Chef', locationName: place, locationId: id);

    test('the id picks it, whatever the name says', () {
      expect(chefLocationColor(chef('Anything', id: 26), scheme), chefLocationColors[26]!.light);
    });

    test('with no id the name picks it, under any name RIT has used', () {
      expect(chefLocationColor(chef('Crossroads'), scheme), chefLocationColors[23]!.light);
      expect(chefLocationColor(chef('The Cafe & Market at Crossroads'), scheme), chefLocationColors[23]!.light);
      expect(chefLocationColor(chef('Gracie’s'), scheme), chefLocationColors[21]!.light);
      expect(chefLocationColor(chef('Ritz Sports Zone'), scheme), chefLocationColors[26]!.light);
    });

    test('an unknown location gets the muted text colour', () {
      expect(chefLocationColor(chef('Somewhere new'), scheme), scheme.onSurfaceVariant);
      expect(chefLocationColor(chef('', id: 9999), scheme), scheme.onSurfaceVariant);
    });

    test('dark picks the dark colour', () {
      expect(
        chefLocationColor(chef('RITZ'), _scheme(Brightness.dark)),
        chefLocationColors[26]!.dark,
      );
    });
  });

  test('MenuItem reads the location id from the feed', () {
    final item = MenuItem.fromJson({'id': 1, 'name': 'Chef', 'location_name': 'RITZ', 'location_id': 26});
    expect(item.locationId, 26);
    expect(MenuItem.fromJson({'id': 1, 'name': 'Chef'}).locationId, isNull);
  });
}
