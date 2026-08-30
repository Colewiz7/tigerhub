/// Parity for the turbo-stream decoder and the campus places it feeds.
///
/// This is the hairiest parser in the port. turbo-stream is a flattened value
/// graph where every value is an index into one array, object keys are
/// themselves indices, and the graph can contain cycles. Getting it subtly
/// wrong would not throw, it would quietly return a different graph, so it is
/// checked against the backend's decoder over two real 260 KB payloads rather
/// than over a toy example.
///
/// 236 places across four kinds, every field compared.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/data/turbo_stream.dart';

void main() {
  test('campus places decode identically to the backend', () {
    final actual = <String, List<Map<String, dynamic>>>{};
    for (final id in [35, 19]) {
      final raw = File('test/fixtures/maps_category_$id.data')
          .readAsStringSync();
      parseCampusPlaces(raw).forEach((subId, places) {
        actual[placeKinds[subId]!.$1] = places
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      });
    }

    final expected = (jsonDecode(
      File('test/golden/campus_places_parse.json').readAsStringSync(),
    ) as Map<String, dynamic>);

    expect(
      actual.keys.toSet(),
      expected.keys.toSet(),
      reason: 'a whole kind went missing or appeared',
    );

    for (final kind in expected.keys) {
      final want = (expected[kind] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final got = actual[kind]!;
      expect(got.length, want.length, reason: '$kind place count differs');

      for (var i = 0; i < want.length; i++) {
        for (final key in want[i].keys) {
          expect(
            got[i][key],
            equals(want[i][key]),
            reason: '$kind "${want[i]['name']}" field "$key" differs',
          );
        }
      }
    }
  });

  test(
    'map geometry is projected separately from parity-tested place rows',
    () {
      final raw = File('test/fixtures/maps_category_35.data')
          .readAsStringSync();
      final places = parseCampusPlaces(raw);
      final features = parseCampusMapFeatures(raw);

      expect(features, isNotEmpty);
      expect(
        features.every(
          (feature) => feature['geometry'] is Map<String, dynamic>,
        ),
        isTrue,
      );
      expect(
        features.any(
          (feature) =>
              (feature['geometry'] as Map<String, dynamic>)['type'] == 'Point',
        ),
        isTrue,
      );
      expect(
        places.values
            .expand((rows) => rows)
            .every((row) => !row.containsKey('geometry')),
        isTrue,
        reason: 'the established place contract must remain unchanged',
      );
    },
  );

  group('turbo stream', () {
    test('resolves values through the index table', () {
      // Index 0 is the root. {"_1": 2} means "key at index 1, value at index 2".
      expect(decodeTurboStream('[{"_1":2},"name","Gracie\'s"]'), {
        'name': "Gracie's",
      });
    });

    test('reads the negative sentinels', () {
      // A sentinel counts where an index reference is expected, so these are
      // the array's elements, not values parked elsewhere in the table.
      expect(decodeTurboStream('[[-2,-1]]'), [null, null]);
    });

    test('survives a cycle instead of blowing the stack', () {
      // Index 0 is an object whose "self" key points back at index 0.
      final decoded =
          decodeTurboStream('[{"_1":0},"self"]')! as Map<String, dynamic>;
      expect(decoded.containsKey('self'), isTrue);
      expect(
        identical(decoded['self'], decoded),
        isTrue,
        reason: 'the cycle should resolve to the same object, not recurse',
      );
    });

    test('rejects something that is not turbo-stream', () {
      expect(() => decodeTurboStream(''), throwsA(isA<TurboStreamError>()));
      expect(
        () => decodeTurboStream('not json'),
        throwsA(isA<TurboStreamError>()),
      );
      expect(() => decodeTurboStream('{}'), throwsA(isA<TurboStreamError>()));
    });

    test('finds a key at any depth', () {
      final decoded = decodeTurboStream('[{"_1":2},"a",[3],{"_4":5},"b","x"]');
      expect(findAll(decoded, 'b'), ['x']);
    });
  });
}
