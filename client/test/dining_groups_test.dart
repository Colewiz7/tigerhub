/// The generated dining groups file against the TigerCenter snapshot.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/widgets/app_icon.dart';

void main() {
  late Map<String, dynamic> file;
  late List<Map<String, dynamic>> places;
  late Map<int, String> snapshotNames;

  setUpAll(() {
    file = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
    places = (file['places'] as List<dynamic>).cast<Map<String, dynamic>>();
    final raw = jsonDecode(File('test/fixtures/dining_all.json').readAsStringSync()) as Map<String, dynamic>;
    snapshotNames = {
      for (final l in (raw['locations'] ?? raw['data'] ?? raw['items']) as List<dynamic>)
        (l as Map<String, dynamic>)['id'] as int: l['name'] as String,
    };
    StaticConfig.overrideForTesting({'dining_groups': file});
  });

  String groupOf(String name) {
    final id = snapshotNames.entries.firstWhere((e) => e.value.contains(name)).key;
    return StaticConfig.instance.diningGroupFor(id);
  }

  test('every dining id sits in exactly one group', () {
    final ids = [for (final p in places) p['id'] as int];
    expect(ids.toSet().length, ids.length);
    expect(ids.toSet(), snapshotNames.keys.toSet());
    final groups = {for (final g in StaticConfig.instance.diningGroups) g.id};
    for (final p in places) {
      expect(groups, contains(p['group']));
    }
  });

  test('the group names are the seven agreed ones, Other last', () {
    expect([for (final g in StaticConfig.instance.diningGroups) g.name], [
      'Dorm side',
      'SHED',
      'Student Alumni Union',
      'Global Village',
      'Golisano',
      'RIT Inn',
      'Other',
    ]);
  });

  test('carries last_verified and source', () {
    expect(file['last_verified'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect((file['source'] as String).isNotEmpty, isTrue);
  });

  test('areas follow the decisions', () {
    expect(groupOf("Sol's"), 'dorm_side');
    expect(groupOf('Crossroads'), 'global_village');
    expect(groupOf('Patio'), 'global_village');
    expect(groupOf('Bytes'), 'other');
    expect(groupOf('USB'), 'other');
    expect(groupOf('Petals'), 'rit_inn');
    expect(groupOf('CTRL ALT'), 'golisano');
    final inn = places.where((p) => p['group'] == 'rit_inn');
    expect(inn.length, 1);
  });

  test('a place missing from the table lands in other', () {
    expect(StaticConfig.instance.diningGroupFor(99999), 'other');
  });

  test('Crossroads is a dining hall by venue type', () {
    expect(iconForVenue('The Cafe & Market at Crossroads'), AppIconKind.diningHall);
  });
}
