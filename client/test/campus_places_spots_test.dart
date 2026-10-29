/// DSP Field, the one outdoor spot read from RIT's own feature list.
///
/// RIT draws it as a point but files it under no sub-category, so the
/// sub-category parser never saw it and its alias row could never pin. The
/// court and the bonfire pit are in neither RIT's data nor OpenStreetMap by
/// name, so they stay unpinned, and Judson and Tiger Stadium stay unmapped.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/sources/athletics.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/campus_event_mapper.dart';
import 'package:tigerhub/widgets/campus_map.dart';

const fixtures = [3, 11, 19, 35];

List<Map<String, dynamic>> parseFixture(int id, {String Function(String)? edit}) {
  final raw = File('test/fixtures/maps_category_$id.data').readAsStringSync();
  return parseCampusMapFeatures(edit == null ? raw : edit(raw));
}

List<CampusMapFeature> realFeatures() {
  final seen = <String>{};
  return [
    for (final id in fixtures)
      for (final json in parseFixture(id))
        if (seen.add('${json['kind']}:${json['id']}'))
          CampusMapFeature.fromJson(json),
  ];
}

final dayStart = CampusTime.wall(2026, 8, 30);
final day = DateTime(2026, 8, 30);

CampusEvent event(String location, {String source = 'test'}) => CampusEvent(
  uid: '$source-$location',
  source: source,
  title: location,
  startsAt: dayStart.add(const Duration(hours: 9)),
  location: location,
);

List<MappedEventGroup> pins(String location, {String source = 'test'}) =>
    mapCampusEvents(
      [event(location, source: source)],
      realFeatures(),
      day: day,
    ).groups;

void main() {
  group('the parser', () {
    test('reads DSP Field from the feature list as a _spot point', () {
      for (final id in fixtures) {
        final spots = parseFixture(id).where((f) => f['kind'] == '_spot').toList();
        expect(spots, hasLength(1), reason: 'category $id');
        final spot = spots.single;
        expect(spot['id'], 4655);
        expect(spot['name'], 'DSP Field');
        expect(spot['building'], isNull);
        expect(spot['geometry'], {
          'type': 'Point',
          'coordinates': [-77.66663, 43.084652],
        });
      }
    });

    test('reads only the allowlist, not the other outdoor features', () {
      final spots = [
        for (final id in fixtures)
          for (final f in parseFixture(id))
            if (f['kind'] == '_spot') f['name'],
      ];
      expect(spots.toSet(), {'DSP Field'});
      final names = [
        for (final id in fixtures) for (final f in parseFixture(id)) '${f['name']}',
      ].join('|');
      for (final other in ['Grace Watson Field', 'Greek Lawn', 'Archery Field']) {
        expect(names, isNot(contains(other)), reason: other);
      }
    });

    test('the spot is matched by id, so a rename upstream does not lose it', () {
      final renamed = parseFixture(
        3,
        edit: (raw) => raw.replaceAll('DSP Field', 'Perry Hall Field'),
      );
      final spot = renamed.singleWhere((f) => f['kind'] == '_spot');
      expect(spot['id'], 4655);
      expect(spot['name'], 'Perry Hall Field');
      // the alias names DSP Field, so a renamed spot stops pinning, safely
      expect(
        mapCampusEvents(
          [event('DSP Field')],
          [for (final f in renamed) CampusMapFeature.fromJson(f)],
          day: day,
        ).groups,
        isEmpty,
      );
    });

    test('an unreadable payload gives no spot and no error', () {
      expect(parseCampusMapFeatures('not a payload'), isEmpty);
    });

    test('everything else in a payload comes through beside the spot', () {
      final all = parseFixture(3);
      expect(all.where((f) => f['kind'] != '_spot').length, greaterThan(100));
    });

    test('the fingerprint names the spots, so old snapshots are replaced', () {
      expect(campusPlacesFingerprint, contains('|spots:4655'));
      expect(outdoorSpotIds, {4655});
    });
  });

  group('events', () {
    test('DSP Field events pin to the field, never to DSP', () {
      final groups = pins('DSP Field');
      expect(groups, hasLength(1));
      expect(groups.single.building, 'DSP Field');
      expect(groups.single.coordinate.longitude, -77.66663);
      expect(groups.single.coordinate.latitude, 43.084652);
    });

    test('the volleyball court and the bonfire pit stay unpinned', () {
      expect(pins('Perkins Green Volleyball Court'), isEmpty);
      expect(pins('Grace Watson Bonfire Pit'), isEmpty);
    });

    test('a missing spot gives no pin rather than a neighbour', () {
      final without = [
        for (final f in realFeatures())
          if (f.kind != '_spot') f,
      ];
      final result = mapCampusEvents([event('DSP Field')], without, day: day);
      expect(result.groups, isEmpty);
      expect(result.unmapped, 1);
    });

    test('Judson and Tiger Stadium stay unmapped', () {
      for (final text in [
        'Judson Stadium',
        'Tiger Stadium',
        'Rochester, N.Y. / Judson Stadium',
        'STA',
      ]) {
        expect(pins(text), isEmpty, reason: text);
      }
      expect(
        pins('Rochester, N.Y. / Judson Stadium', source: athleticsSource),
        isEmpty,
      );
      final names = [for (final f in realFeatures()) f.name.toLowerCase()];
      expect(names.where((n) => n.contains('judson')), isEmpty);
    });
  });

  testWidgets('a _spot is not a place, a filter or a pin', (tester) async {
    final spot = CampusMapFeature.fromJson(
      parseFixture(3).firstWhere((f) => f['kind'] == '_spot'),
    );
    expect(spot.kind, '_spot');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CampusMapView(
              result: Result(
                value: Collection(data: [...realFeatures()], stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Outdoor spot'), findsNothing);
    expect(find.text('DSP Field'), findsNothing);
  });
}
