/// The FD MealPlanner location mapping, pinned against the live list.
///
/// This exists because the mapping was wrong for 7 of 12 locations and nothing
/// caught it. The ids had been assumed to run 1..12 in name order. They do not:
/// the real ids skip numbers, and RITZ, The Commons and The College Grind have
/// an accountId that differs from their locationId.
///
/// The failure was silent and worse than a crash. The wrong ids were still
/// valid ids, so RITZ was served Gracie's menu, **including Gracie's
/// allergens**. A dish list that is confidently wrong about allergens is the
/// one failure mode this feature must not have.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  test('every mapped location matches the live FD list by name', () {
    final config = read('assets/config/fd_locations.json');
    final live = (read('test/fixtures/fd_locations_live.json')['data']
        as Map<String, dynamic>)['result'] as List<dynamic>;

    final byName = {
      for (final raw in live)
        (raw as Map<String, dynamic>)['locationName'] as String: raw,
    };

    final mapped = config['locations'] as List<dynamic>;
    expect(mapped, isNotEmpty);

    for (final raw in mapped) {
      final entry = raw as Map<String, dynamic>;
      final name = entry['fd_name'] as String;
      final real = byName[name];

      expect(real, isNotNull, reason: 'FD no longer publishes "$name"');
      expect(entry['fd_location_id'], real!['locationId'],
          reason: '"$name" has the wrong locationId, which serves another '
              "location's menu and allergens rather than failing");
      expect(entry['fd_account_id'], real['accountId'],
          reason: '"$name" has the wrong accountId');
    }
  });

  test('a dining id is never mapped to two FD locations', () {
    final config = read('assets/config/fd_locations.json');
    final ids = [
      for (final e in config['locations'] as List<dynamic>)
        (e as Map<String, dynamic>)['dining_id'],
    ];
    expect(ids.toSet().length, ids.length,
        reason: 'two FD locations claiming one dining id makes the menu shown '
            'depend on iteration order');
  });

  test('nothing claims to be halal or kosher', () {
    // docs/notes.md 7.7: FD does not tag either, so nothing may ever be labelled
    // that way, and filtering on the pork tag as a proxy would be wrong.
    final raw = File('assets/config/fd_locations.json').readAsStringSync();
    expect(raw.toLowerCase(), isNot(contains('halal')));
    expect(raw.toLowerCase(), isNot(contains('kosher')));
  });
}
