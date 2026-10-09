/// Records missing a required time field are dropped and counted, never "now".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';

Map<String, dynamic> _event(
  String uid, [
  Map<String, dynamic> extra = const {},
]) => {'uid': uid, 'starts_at': '2026-03-01T10:00:00Z', ...extra};

Map<String, dynamic> _span([Map<String, dynamic> extra = const {}]) => {
  'opens_at': '2026-03-01T08:00:00Z',
  'closes_at': '2026-03-01T17:00:00Z',
  ...extra,
};

Map<String, dynamic> _location(int id, List<Map<String, dynamic>> today) => {
  'id': id,
  'name': 'L$id',
  'today': today,
};

void main() {
  final start = DateTime.utc(2026, 3, 1, 10);

  test('events missing starts_at are dropped and counted', () {
    final bad = _event('b')..remove('starts_at');
    final badType = _event('c', {'starts_at': 12});
    final json = {
      'data': [_event('a'), bad, badType, _event('d')],
    };
    final c = Collection.fromJson(json, CampusEvent.fromJson);
    expect(c.data.map((e) => e.uid), ['a', 'd']);
    expect(c.dropped, 2);
    expect(c.data.every((e) => e.startsAt.isAtSameMomentAs(start)), isTrue);
  });

  test('optional ends_at stays null, not now', () {
    final c = Collection.fromJson({
      'data': [_event('a')],
    }, CampusEvent.fromJson);
    expect(c.data.single.endsAt, isNull);
    expect(c.dropped, 0);
  });

  test('bad spans are dropped, the location and valid spans stay', () {
    final noOpen = _span()..remove('opens_at');
    final noClose = _span()..remove('closes_at');
    final json = {
      'data': [
        _location(1, [_span()]),
        _location(2, [noOpen, _span()]),
        _location(3, [noClose]),
        _location(4, []),
      ],
    };
    final c = Collection.fromJson(json, DiningLocation.fromJson);
    expect(c.data.map((l) => l.id), [1, 2, 3, 4]);
    expect(c.data.map((l) => l.today.length), [1, 1, 0, 0]);
    expect(c.dropped, 2);
    final kept = c.data[1].today.single.opensAt;
    expect(kept.isAtSameMomentAs(DateTime.utc(2026, 3, 1, 8)), isTrue);
  });

  test('all spans bad falls back to hours unavailable', () {
    final noOpen = _span()..remove('opens_at');
    final loc = _location(1, [noOpen])
      ..['opens_at'] = '2026-03-01T08:00:00Z'
      ..['closes_at'] = '2026-03-01T17:00:00Z'
      ..['next_transition'] = '2026-03-01T17:00:00Z';
    final l = DiningLocation.fromJson(loc);
    expect(l.opensAt, isNull);
    expect(l.closesAt, isNull);
    expect(l.nextTransition, isNull);
    expect(l.droppedNested, 1);
  });

  test('a location with no spans at all keeps its own times', () {
    final loc = _location(1, [])..['opens_at'] = '2026-03-01T08:00:00Z';
    expect(DiningLocation.fromJson(loc).opensAt, isNotNull);
  });

  test('optional dining times stay null', () {
    final c = Collection.fromJson({
      'data': [_location(1, [])],
    }, DiningLocation.fromJson);
    expect(c.data.single.opensAt, isNull);
    expect(c.data.single.closesAt, isNull);
    expect(c.data.single.nextTransition, isNull);
  });

  test('menu day without service_date is dropped and counted', () {
    final bad = MenuDay.fromJson({
      'location_id': 1,
      'dishes': [
        {'name': 'Soup'},
      ],
    });
    expect(bad.dropped, 1);
    expect(bad.serviceDate, isNull);
    expect(bad.dishes, isEmpty);
    final ok = MenuDay.fromJson({
      'location_id': 1,
      'service_date': '2026-03-01',
    });
    expect(ok.dropped, 0);
    expect(ok.serviceDate!.year, 2026);
  });

  test('bad recreation day is dropped, facility and good days stay', () {
    final json = {
      'data': [
        {
          'name': 'Pool',
          'days': [
            {'service_date': '2026-03-01'},
            {'closed': true},
            {'service_date': 'nope'},
          ],
        },
        {
          'name': 'Gym',
          'days': [
            {'service_date': '2026-03-02'},
          ],
        },
      ],
    };
    final c = Collection.fromJson(json, RecreationFacility.fromJson);
    expect(c.data.map((f) => f.days.length), [1, 1]);
    expect(c.dropped, 2);
  });

  test('dropped counts top level and nested items together', () {
    final json = {
      'data': [
        _location(1, [_span()..remove('closes_at')]),
      ],
    };
    expect(Collection.fromJson(json, DiningLocation.fromJson).dropped, 1);
  });

  test('dropped survives copyWith', () {
    final c = Collection.fromJson({
      'data': [
        <String, dynamic>{'uid': 'x'},
      ],
    }, CampusEvent.fromJson);
    expect(c.copyWith(stale: true).dropped, 1);
  });
}
