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

  test('open spans missing opens_at or closes_at drop their location', () {
    final noOpen = _span()..remove('opens_at');
    final noClose = _span()..remove('closes_at');
    final json = {
      'data': [
        _location(1, [_span()]),
        _location(2, [noOpen]),
        _location(3, [noClose]),
        _location(4, [_span(), noOpen]),
        _location(5, []),
      ],
    };
    final c = Collection.fromJson(json, DiningLocation.fromJson);
    expect(c.data.map((l) => l.id), [1, 5]);
    expect(c.dropped, 3);
    expect(
      c.data.first.today.single.opensAt.isAtSameMomentAs(
        DateTime.utc(2026, 3, 1, 8),
      ),
      isTrue,
    );
  });

  test('optional dining times stay null', () {
    final c = Collection.fromJson({
      'data': [_location(1, [])],
    }, DiningLocation.fromJson);
    expect(c.data.single.opensAt, isNull);
    expect(c.data.single.closesAt, isNull);
    expect(c.data.single.nextTransition, isNull);
  });

  test('menu day without service_date throws instead of using now', () {
    expect(
      () => MenuDay.fromJson({'location_id': 1}),
      throwsA(isA<MissingTimeException>()),
    );
    final ok = MenuDay.fromJson({
      'location_id': 1,
      'service_date': '2026-03-01',
    });
    expect(ok.serviceDate.year, 2026);
  });

  test('recreation days without service_date drop the facility', () {
    final json = {
      'data': [
        {
          'id': 1,
          'name': 'Good',
          'days': [
            {'service_date': '2026-03-01'},
          ],
        },
        {
          'id': 2,
          'name': 'Bad',
          'days': [
            {'closed': true},
          ],
        },
      ],
    };
    final c = Collection.fromJson(json, RecreationFacility.fromJson);
    expect(c.data.length, 1);
    expect(c.dropped, 1);
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
