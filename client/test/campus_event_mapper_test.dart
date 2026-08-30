import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_event_mapper.dart';

const features = [
  CampusMapFeature(
    id: 1,
    kind: 'water',
    kindName: 'Water fountains',
    name: 'GOL fountain',
    geometryType: 'Point',
    coordinates: [
      [GeoCoordinate(-77.68, 43.08)],
    ],
    building: 'GOL',
  ),
  CampusMapFeature(
    id: 2,
    kind: 'aed',
    kindName: 'Defibrillators',
    name: 'SHED AED',
    geometryType: 'Point',
    coordinates: [
      [GeoCoordinate(-77.67, 43.09)],
    ],
    building: 'SHED',
  ),
];

CampusEvent event(String uid, String? location, DateTime startsAt) =>
    CampusEvent(
      uid: uid,
      source: 'test',
      title: 'Event $uid',
      startsAt: startsAt,
      location: location,
    );

void main() {
  final day = DateTime(2026, 8, 30);

  test('exact building abbreviations map and same-building events cluster', () {
    final result = mapCampusEvents(
      [
        event('1', 'GOL-1400', day.add(const Duration(hours: 9))),
        event('2', 'GOL 2400', day.add(const Duration(hours: 10))),
      ],
      features,
      day: day,
    );

    expect(result.mapped, 2);
    expect(result.unmapped, 0);
    expect(result.groups, hasLength(1));
    expect(result.groups.single.building, 'GOL');
    expect(result.groups.single.events.map((e) => e.uid), ['1', '2']);
  });

  test(
    'partial words, unknown buildings, and missing locations stay unmapped',
    () {
      final result = mapCampusEvents(
        [
          event('1', 'GOLD room', day.add(const Duration(hours: 9))),
          event('2', 'Unknown Hall', day.add(const Duration(hours: 10))),
          event('3', null, day.add(const Duration(hours: 11))),
        ],
        features,
        day: day,
      );

      expect(result.mapped, 0);
      expect(result.unmapped, 3);
    },
  );

  test('a location naming two buildings is ambiguous and is not pinned', () {
    final result = mapCampusEvents(
      [event('1', 'GOL / SHED', day.add(const Duration(hours: 9)))],
      features,
      day: day,
    );

    expect(result.groups, isEmpty);
    expect(result.unmapped, 1);
  });

  test('events outside the selected day do not affect its counts', () {
    final result = mapCampusEvents(
      [event('1', 'GOL', day.add(const Duration(days: 1)))],
      features,
      day: day,
    );

    expect(result.mapped, 0);
    expect(result.unmapped, 0);
  });
}
