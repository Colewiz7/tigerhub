/// Workday time clocks, and the categories that were already being downloaded
/// and thrown away.
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

  group('categories that were already on the wire', () {
    // Parent 47, "Other", was already fetched for its outlines and yielded
    // exactly zero registered kinds: every point in it was parsed and dropped
    // because nothing claimed the sub-category. Registering them costs no
    // extra request at all.
    final other = File(
      'test/fixtures/campus_places_other.data',
    ).readAsStringSync();

    test('parent 47 now yields the kinds it was carrying all along', () {
      final bySub = parseCampusPlaces(other);
      expect(bySub[527]!.length, 5, reason: 'printers');
      expect(bySub[236]!.length, 7, reason: 'study areas');
      expect(bySub[211]!.length, 20, reason: 'computer labs');
      expect(bySub[528]!.length, 4, reason: 'connection hub');
    });

    test('and every one of them is mapped', () {
      final features = parseCampusMapFeatures(other);
      for (final kind in [
        'printer',
        'study_area',
        'computer_lab',
        'connection_hub',
      ]) {
        final mapped = features.where((f) => f['kind'] == kind);
        expect(mapped, isNotEmpty, reason: kind);
        for (final feature in mapped) {
          final coordinates =
              (feature['geometry'] as Map)['coordinates'] as List<dynamic>;
          expect(coordinates[0] as double, inInclusiveRange(-77.70, -77.65));
          expect(coordinates[1] as double, inInclusiveRange(43.07, 43.10));
        }
      }
    });

    test('the kinds added from parents already in the list are registered', () {
      // These live under 7 (Dining) and 27 (Amenities), both long since
      // fetched. Same story: downloaded, then dropped for want of a kind.
      expect(placeKinds[87], ('vending', 'Vending machines'));
      expect(placeKinds[83], ('convenience', 'Convenience stores'));
      expect(placeKinds[279], ('lactation', 'Lactation rooms'));
      for (final parent in [7, 27, 47]) {
        expect(placeParents, contains(parent));
      }
    });
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
