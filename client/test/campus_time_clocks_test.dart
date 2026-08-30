/// Workday time clocks.
///
/// Cole asked for them on the map. They were reachable all along: CLAUDE.md
/// 7.9.2 recorded that the map's category ids run into the hundreds and that
/// kiosks were "partly reachable" but never enumerated, because pulling the
/// category menu out needed a real turbo-stream decoder rather than the
/// targeted extractor. We have one now, so the menu embedded in any category
/// response names them: 199, "Workday time clocks", under parent 39,
/// "Employees".
///
/// Pinned against a captured payload so an upstream reshuffle is caught here
/// rather than by the pins quietly disappearing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/campus_places.dart';

void main() {
  final raw = File(
    'test/fixtures/campus_places_employees.data',
  ).readAsStringSync();

  test('the Employees parent is actually fetched', () {
    // Registering the kind without fetching its parent is the silent failure
    // here: the app would simply never see a clock.
    expect(placeParents, contains(39));
    expect(placeKinds[199], ('time_clock', 'Workday time clocks'));
  });

  test('every clock arrives with a real position', () {
    final clocks = parseCampusMapFeatures(
      raw,
    ).where((f) => f['kind'] == 'time_clock').toList();

    expect(clocks.length, 62);
    for (final clock in clocks) {
      final geometry = clock['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'Point');
      final coordinates = geometry['coordinates'] as List<dynamic>;
      // On campus, not at null island or in the wrong hemisphere.
      expect(coordinates[0] as double, inInclusiveRange(-77.70, -77.65));
      expect(coordinates[1] as double, inInclusiveRange(43.07, 43.10));
    }
  });

  test('a clock says where in the building it is', () {
    // A pin on a building is not enough for something inside one. The floor,
    // the room and RIT's own clock id are what actually find it.
    final clocks = parseCampusMapFeatures(
      raw,
    ).where((f) => f['kind'] == 'time_clock');
    final nrh = clocks.firstWhere(
      (f) => (f['name'] as String).contains('Nathaniel Rochester'),
    );

    expect(nrh['building'], 'DSP');
    expect(nrh['floor'], '1st floor');
    expect(nrh['room'], '1090');
    expect(nrh['note'], contains('Clock ID'));
  });

  test('the places list carries them too, not just the map', () {
    final bySub = parseCampusPlaces(raw);
    expect(bySub[199], isNotNull);
    expect(bySub[199]!.length, 62);
    expect(
      bySub[199]!.every((p) => (p['name'] as String).isNotEmpty),
      isTrue,
    );
  });
}
