/// The map needs geometry, not just pins.
///
/// It was a bunch of dots placed around rather than a map, and the cause
/// was which categories were fetched. The place
/// categories carry the pins; the shape of campus lives in categories that were
/// never requested, so the backdrop had twenty buildings in it, all of them
/// incidental LEED ones from Sustainability.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/campus_places.dart';

void main() {
  List<Map<String, dynamic>> parse(List<int> ids) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final id in ids) {
      final file = File('test/fixtures/maps_category_$id.data');
      if (!file.existsSync()) continue;
      for (final feature in parseCampusMapFeatures(file.readAsStringSync())) {
        if (seen.add('${feature['kind']}:${feature['id']}')) out.add(feature);
      }
    }
    return out;
  }

  bool isArea(Map<String, dynamic> f) {
    final g = f['geometry'];
    return g is Map && (g['type'] == 'Polygon' || g['type'] == 'MultiPolygon');
  }

  test('the buildings category is fetched at all', () {
    // The whole bug in one line: 3 was not in the list.
    expect(placeParents, contains(3), reason: 'no buildings means no map');
  });

  test('buildings dwarf what the place categories happen to include', () {
    final incidental = parse([35, 19]).where(isArea).length;
    final withBuildings = parse([3, 35, 19]).where(isArea).length;

    expect(incidental, lessThan(30),
        reason: 'this is the scatter-of-dots case, kept as the comparison');
    // 143 unique building outlines, seven times the incidental twenty.
    expect(withBuildings, greaterThan(140));
  });

  test('parking lots come through as geometry, not pins', () {
    // The lots are listed under several permit sub-categories, so the raw
    // payload repeats them; these are the distinct outlines.
    final features = parse([11]);
    expect(features.where(isArea).length, features.length,
        reason: 'parking should contribute geometry only, never pins');
    expect(features.where(isArea).length, greaterThan(15));
  });

  test('backdrop geometry names its own family', () {
    // A parking lot and a lecture hall are both backdrop. Being able to tell
    // them apart is what lets them be drawn differently.
    final names = parse([3, 11])
        .where(isArea)
        .map((f) => '${f['kind_name']}')
        .toSet();

    expect(names, isNot(contains('Campus structure')),
        reason: 'every backdrop feature fell back to the generic label');
    expect(names.any((n) => n.contains('Building')), isTrue);
    expect(names.any((n) => n.contains('Parking')), isTrue);
  });

  test('buildings carry the abbreviation event placement needs', () {
    // The spec allows a pin only on an exact building match, so this is the
    // table that makes event placement possible at all.
    final abbreviated =
        parse([3]).where((f) => f['building'] != null).length;
    expect(abbreviated, greaterThan(50),
        reason: 'not every outline is a named building, but most halls are');
  });

  test('their point features are still ignored', () {
    // These categories are fetched for geometry. Their points belong to kinds
    // that are not student facing, and letting them in would put printer and
    // office pins all over the map.
    final points = parse([3, 11]).where((f) => !isArea(f)).length;
    expect(points, 0);
  });
}
