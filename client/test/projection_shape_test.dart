/// The projections must produce what the models actually read.
///
/// This exists because two of them did not, and nothing caught it. The scraping
/// was correct, the parity tests passed, and the UI rendered blank:
///
///   recreation   returned flat rows, but RecreationFacility reads
///                {name, days:[{service_date, closed, spans:[...]}]}
///   places       returned "name", but PlaceKind reads "kind_name"
///
/// Neither failed. A missing key is null, null becomes an empty string or an
/// empty list, and the card renders as though the data simply was not there.
/// That is indistinguishable from being offline, which is the worst way for
/// this app in particular to break.
///
/// So each projection is run over real captured data and parsed through the
/// real model, and the result is asserted to actually contain something.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/data/sources/makerspace.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/models/api_models.dart';

void main() {
  test('recreation hours survive the round trip into the model', () {
    final rows = parseRecreation(
      File('test/fixtures/recreation.html').readAsStringSync(),
      today: DateTime.utc(2026, 8, 30),
    );
    final projected = recreationFacilities({'rows': rows});

    final facilities =
        projected.map(RecreationFacility.fromJson).toList(growable: false);

    expect(facilities, isNotEmpty, reason: 'no facilities came through');
    expect(facilities.every((f) => f.name.isNotEmpty), isTrue,
        reason: 'a facility with no name renders as a blank heading');
    expect(facilities.every((f) => f.days.isNotEmpty), isTrue,
        reason: 'a facility with no days renders as an empty card');

    // The pool is the case the nesting exists for: several sessions in one day.
    final multiSession = facilities
        .expand((f) => f.days)
        .any((d) => d.spans.length > 1);
    expect(multiSession, isTrue,
        reason: 'a day with several sessions must keep them separate, or the '
            'card claims the pool is open straight through the afternoon');

    // Every open day must carry usable times.
    for (final facility in facilities) {
      for (final day in facility.days) {
        if (day.closed) continue;
        expect(day.spans, isNotEmpty,
            reason: '${facility.name} is open but has no hours');
      }
    }
  });

  test('place kinds survive the round trip into the model', () {
    final kinds = <String, List<Map<String, dynamic>>>{};
    for (final id in [35, 19]) {
      parseCampusPlaces(
        File('test/fixtures/maps_category_$id.data').readAsStringSync(),
      ).forEach((subId, places) => kinds[placeKinds[subId]!.$1] = places);
    }

    final summary = placeKindSummary({'kinds': kinds})
        .map(PlaceKind.fromJson)
        .toList(growable: false);

    expect(summary, isNotEmpty);
    expect(summary.every((k) => k.kind.isNotEmpty), isTrue);
    expect(summary.every((k) => k.kindName.isNotEmpty), isTrue,
        reason: 'a blank kindName is the exact bug this test was written for');
    expect(summary.every((k) => k.count > 0), isTrue);
  });

  test('individual places survive the round trip into the model', () {
    final kinds = <String, List<Map<String, dynamic>>>{};
    parseCampusPlaces(
      File('test/fixtures/maps_category_35.data').readAsStringSync(),
    ).forEach((subId, places) => kinds[placeKinds[subId]!.$1] = places);

    final water = placesOfKind({'kinds': kinds}, 'water')
        .map(CampusPlace.fromJson)
        .toList(growable: false);

    expect(water, isNotEmpty, reason: 'the 96 hydration stations went missing');
    expect(water.every((p) => p.name.isNotEmpty), isTrue);
    expect(water.any((p) => (p.building ?? '').isNotEmpty), isTrue,
        reason: 'the building is what makes a fountain findable');
  });

  test('makerspace rooms survive the round trip into the model', () {
    final equipment = jsonDecode('''
      {"data": {"equipments": [
        {"id": 1, "name": "Lathe", "subName": "", "inUse": false,
         "numAvailable": 2, "numInUse": 0, "archived": false,
         "room": {"id": 1, "name": "Manual Shop"}},
        {"id": 2, "name": "Mill", "subName": " Bridgeport ", "inUse": true,
         "numAvailable": 0, "numInUse": 1, "archived": false,
         "room": {"id": 1, "name": "Manual Shop"}},
        {"id": 3, "name": "Retired", "subName": "", "inUse": false,
         "numAvailable": 1, "numInUse": 0, "archived": true,
         "room": {"id": 2, "name": "Old Shop"}}
      ]}}
    ''') as Map<String, dynamic>;

    final snapshot = {'equipment': parseMakerspace(equipment)};

    final rooms = roomSummary(snapshot).map(RoomSummary.fromJson).toList();
    expect(rooms.length, 1, reason: 'the archived machine dragged in a room');
    expect(rooms.single.room, 'Manual Shop');
    expect(rooms.single.machines, 2);
    expect(rooms.single.available, 2);
    expect(rooms.single.inUse, 1);

    // There is no Equipment model: the UI only ever shows per room totals, so
    // the raw list is checked as maps rather than through a model.
    final all = equipmentIn(snapshot, null);
    expect(all.length, 2, reason: 'archived equipment must not be listed');
    expect(all.first['name'], 'Lathe', reason: 'sorted by room then name');
    expect(all.last['sub_name'], 'Bridgeport', reason: 'sub_name is trimmed');
  });
}
