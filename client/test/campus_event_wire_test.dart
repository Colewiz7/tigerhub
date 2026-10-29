/// The reviewed alias table drives where events pin on the campus map.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/merge_events.dart';
import 'package:tigerhub/data/sources/athletics.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/data/sources/campusgroups.dart';
import 'package:tigerhub/data/sources/drupal_events.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/widgets/campus_event_mapper.dart';

CampusMapFeature point(
  int id,
  String name,
  double lon,
  double lat, {
  String? building,
}) => CampusMapFeature(
  id: id,
  kind: 'water',
  kindName: 'Water fountains',
  name: name,
  geometryType: 'Point',
  coordinates: [
    [GeoCoordinate(lon, lat)],
  ],
  building: building,
);

CampusMapFeature outline(int id, String building, double lon, double lat) =>
    CampusMapFeature(
      id: id,
      kind: '_campus',
      kindName: 'Academic Building',
      name: building,
      geometryType: 'Polygon',
      coordinates: [
        [
          GeoCoordinate(lon, lat),
          GeoCoordinate(lon + 0.001, lat),
          GeoCoordinate(lon + 0.001, lat + 0.001),
          GeoCoordinate(lon, lat + 0.001),
        ],
      ],
      building: building,
    );

final features = [
  point(1, 'SHED fountain', -77.671, 43.085, building: 'SHD'),
  outline(2, 'GOL', -77.680, 43.084),
  outline(3, 'DSP', -77.676, 43.083),
  outline(4, 'GOR', -77.672, 43.085),
  outline(5, 'GLE', -77.679, 43.086),
  outline(6, 'GVP', -77.667, 43.081),
  outline(7, 'KGH', -77.666, 43.084),
  outline(8, 'SAU', -77.675, 43.0845),
  outline(9, 'RHB', -77.669, 43.0835),
  point(20, 'DSP Field', -77.677, 43.0825),
];

final dayStart = CampusTime.wall(2026, 8, 30);
final day = DateTime(2026, 8, 30);

CampusEvent event(
  String location, {
  String? building,
  String source = 'test',
  String? room,
}) => CampusEvent(
  uid: '$source-$location-$building',
  source: source,
  title: location,
  startsAt: dayStart.add(const Duration(hours: 9)),
  location: location,
  building: building,
  room: room,
);

CampusEventMapResult map(
  List<CampusEvent> events, [
  List<CampusMapFeature>? on,
]) => mapCampusEvents(events, on ?? features, day: day);

String? pinned(CampusEvent e, [List<CampusMapFeature>? on]) {
  final result = map([e], on);
  return result.groups.isEmpty ? null : result.groups.single.building;
}

void main() {
  group('codes the map spells differently', () {
    test('SHED-3300 pins to the map code SHD', () {
      expect(pinned(event('SHED-3300')), 'SHD');
    });

    test('a venue name pins to its building', () {
      expect(pinned(event('Ingle Auditorium'), [outline(1, 'SAU', -77.6, 43)]),
          'SAU');
    });
  });

  group('Drupal building and room', () {
    test('a bare room pins to the building field', () {
      expect(pinned(event('1660', building: 'Golisano Hall')), 'GOL');
    });

    test('an explicit code beats the building field', () {
      expect(
        pinned(event('Campus Center PRISM (CPC-1030)',
            building: 'Liberal Arts Hall'),
            [...features, point(30, 'CPC fountain', -77.7, 43.1, building: 'CPC')]),
        'CPC',
      );
    });

    test('a bare room with no known building stays unpinned', () {
      expect(pinned(event('1660')), isNull);
      expect(pinned(event('1660', building: 'Virtual')), isNull);
    });
  });

  group('never pin to a neighbouring building', () {
    test('Gordon Atrium is GLE, not GOR', () {
      expect(pinned(event('GLE-2955 Gordon Atrium')), 'GLE');
      expect(pinned(event('Gordon Atrium')), 'GLE');
    });

    test('a string naming two buildings stays unpinned', () {
      expect(pinned(event('GOL / SHED-3300')), isNull);
      expect(pinned(event('Grace Watson and Kate Gleason GOL')), isNull);
    });

    test('Clark A is the union, not Clark Gymnasium', () {
      expect(pinned(event('2520 Clark A Conference Room')), 'SAU');
    });

    test('Cybersecurity next to Golisano resolves to one building only', () {
      final cyb = [...features, point(40, 'CYB AED', -77.6805, 43.0845, building: 'CYB')];
      expect(pinned(event('Cybersecurity Golisano Hall CYB 1710'), cyb), 'CYB');
    });
  });

  group('outdoor spots use their own feature', () {
    test('DSP Field pins to the field, not the DSP building', () {
      final result = map([event('DSP Field')]);
      expect(result.groups, hasLength(1));
      final group = result.groups.single;
      expect(group.building, 'DSP Field');
      expect(group.coordinate.longitude, -77.677);
    });

    test('with no such feature the pin is dropped', () {
      final without = [
        for (final f in features)
          if (f.name != 'DSP Field') f,
      ];
      final result = map([event('DSP Field')], without);
      expect(result.groups, isEmpty);
      expect(result.unmapped, 1);
    });

    test('the volleyball court and bonfire pit never fall back to a building',
        () {
      expect(pinned(event('Perkins Green Volleyball Court')), isNull);
      expect(pinned(event('Grace Watson Bonfire Pit')), isNull);
    });
  });

  group('stays unmapped', () {
    test('Global Village alone', () {
      expect(pinned(event('Global Village')), isNull);
      expect(pinned(event('GV Plaza')), isNull);
    });

    test('a Global Village building by name or code pins', () {
      expect(pinned(event('GV 400 First Floor Kitchen')), 'GVP');
      expect(pinned(event('GVP-1250 Wellness Studio')), 'GVP');
    });

    test('Chabad House, even when a map code is nearby', () {
      expect(
        pinned(event('Chabad house - 3018 East River Road - off GOL')),
        isNull,
      );
      expect(pinned(event('Chabad House', building: 'Golisano Hall')), isNull);
    });

    test('Judson Stadium, even beside a building code', () {
      expect(
        pinned(event('Rochester, N.Y. / Judson Stadium',
            source: athleticsSource)),
        isNull,
      );
      expect(pinned(event('Judson Stadium GOR side')), isNull);
    });

    test('virtual events with a code in the text', () {
      expect(pinned(event('Online Only - GOL link')), isNull);
      expect(pinned(event('https://rit.zoom.us/j/GOL')), isNull);
    });
  });

  group('athletics', () {
    test('Judson Pool is in Gordon Field House', () {
      expect(
        pinned(event('Rochester, N.Y. / Judson Pool', source: athleticsSource)),
        'GOR',
      );
    });

    test('an away game is not pinned', () {
      expect(
        pinned(event('Syracuse, N.Y. / GOL Field', source: athleticsSource)),
        isNull,
      );
    });

    test('a Drupal copy of a home game keeps its venue', () {
      expect(
        pinned(event('Rochester, N.Y., Gordon Field House',
            building: 'George Eastman Hall')),
        'GOR',
      );
    });
  });

  group('previous behaviour is kept', () {
    test('an exact map code with no alias row still pins', () {
      expect(pinned(event('KGH 2000')), 'KGH');
    });

    test('two exact codes with no alias rows stay ambiguous', () {
      expect(pinned(event('KGH / RHB lounge')), isNull);
    });
  });

  group('point-only buildings', () {
    test('pin at the amenity point nearest the average', () {
      final points = [
        point(1, 'a', -77.600, 43.000, building: 'SAU'),
        point(2, 'b', -77.610, 43.010, building: 'SAU'),
        point(3, 'c', -77.640, 43.040, building: 'SAU'),
      ];
      final result = map([event('SAU 1829 Room')], points);
      final spot = result.groups.single.coordinate;
      expect([spot.longitude, spot.latitude], [-77.610, 43.010]);
    });
  });

  test('pinned and unpinned counts on the cached fixtures', () {
    final byKey = <String, Map<String, dynamic>>{};
    for (final id in [3, 11, 19, 35]) {
      final raw = File('test/fixtures/maps_category_$id.data');
      for (final f in parseCampusMapFeatures(raw.readAsStringSync())) {
        byKey.putIfAbsent('${f['kind']}:${f['id']}', () => f);
      }
    }
    final map_ = [for (final f in byKey.values) CampusMapFeature.fromJson(f)];

    final raws = <Map<String, dynamic>>[
      ...parseCampusGroups(
        File('test/fixtures/campusgroups.ics').readAsStringSync(),
      ),
      ...parseAthletics(
        File('test/fixtures/athletics.ics').readAsStringSync(),
      ),
      ...parseDrupal(
        jsonDecode(File('test/fixtures/drupal_events.json').readAsStringSync())
            as List<dynamic>,
      ),
    ];
    final events = [
      for (final raw in mergeDuplicateEvents(raws)) CampusEvent.fromJson(raw),
    ];

    final days = {
      for (final e in events) CampusTime.dateOf(e.startsAt),
    };
    var pinnedCount = 0;
    var unpinnedCount = 0;
    final codes = <String, int>{};
    for (final d in days) {
      final result = mapCampusEvents(events, map_, day: d);
      pinnedCount += result.mapped;
      unpinnedCount += result.unmapped;
      for (final g in result.groups) {
        codes[g.building] = (codes[g.building] ?? 0) + g.events.length;
      }
    }

    expect(events.length, 1440);
    expect(pinnedCount + unpinnedCount, events.length);
    expect(pinnedCount, 705);
    expect(unpinnedCount, 735);
    expect(codes['RKA'], 241, reason: 'RIT FoodShare is the biggest row');
  });
}
