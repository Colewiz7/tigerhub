/// Records missing a required time field are dropped and counted, never "now".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';

class _FixedBackend implements Backend {
  _FixedBackend(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => body;

  @override
  void close() {}
}

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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

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

  test('a location with no spans at all shows hours unavailable', () {
    final loc = _location(1, [])..['opens_at'] = '2026-03-01T08:00:00Z';
    final l = DiningLocation.fromJson(loc);
    expect(l.opensAt, isNull);
    expect(l.droppedNested, 0);
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

  test(
    'ApiClient.menu reports an undated menu as absent with one drop',
    () async {
      final bad = {
        'location_id': 1,
        'dishes': [
          {'name': 'Soup'},
        ],
      };
      final r = await ApiClient(backend: _FixedBackend(bad)).menu(1).last;
      expect(r.value, isNull);
      expect(r.dropped, 1);
      final ok = {'location_id': 1, 'service_date': '2026-03-01'};
      final g = await ApiClient(backend: _FixedBackend(ok)).menu(1).last;
      expect(g.value!.serviceDate.year, 2026);
      expect(g.dropped, 0);
    },
  );

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

  test('dropped counts top level and nested items together', () {
    final json = {
      'data': [
        _location(1, [_span()..remove('closes_at')]),
      ],
    };
    expect(Collection.fromJson(json, DiningLocation.fromJson).dropped, 1);
  });

  test('a top level drop and a nested drop both count', () {
    final json = {
      'data': [
        _location(1, [_span(), _span()..remove('closes_at')]),
        {'bad': true},
        _location(3, [_span()]),
      ],
    };
    final c = Collection.fromJson(json, (j) {
      if (j['bad'] == true) throw const MissingTimeException('starts_at');
      return DiningLocation.fromJson(j);
    });
    expect(c.data.map((l) => l.id), [1, 3]);
    expect(c.dropped, 2);
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
