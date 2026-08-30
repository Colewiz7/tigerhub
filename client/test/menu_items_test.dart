/// Visiting chefs and specials, which come free from the TigerCenter payload.
///
/// The two differ only in filtering, and getting that backwards is invisible:
/// both render as "nothing on campus today", which is also the correct output
/// on a day when nothing is published.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/tigercenter.dart';

void main() {
  final snapshot = <String, dynamic>{
    'service_date': '2026-08-30',
    'locations': [
      {
        'id': 23,
        'name': 'Crossroads',
        'menus': [
          {'id': 1, 'name': 'Chef Ana', 'category': 'Visiting Chef', 'price': null},
          {'id': 2, 'name': 'Soup of the day', 'category': 'Soup', 'price': '4.00'},
        ],
      },
      {
        'id': 26,
        'name': 'RITZ',
        'menus': [
          {'id': 3, 'name': 'Chef Bo', 'category': 'Visiting Chef', 'price': null},
        ],
      },
    ],
  };

  test('visiting chefs are filtered by category', () {
    final chefs = menuItemsWithCategory(snapshot, visitingChef);
    expect(chefs.map((c) => c['name']), ['Chef Ana', 'Chef Bo']);
    expect(chefs.first['location_name'], 'Crossroads',
        reason: 'the location is the useful half of a visiting chef entry');
    expect(chefs.first['service_date'], '2026-08-30');
  });

  test('specials are everything published, not a "Special" category', () {
    // The server left specials unfiltered. TigerCenter publishes no category
    // called "Special", so filtering on one returns nothing, every day,
    // indistinguishable from a quiet day.
    final specials = menuItemsWithCategory(snapshot, null);
    expect(specials.length, 3);
    expect(
      menuItemsWithCategory(snapshot, 'Special'),
      isEmpty,
      reason: 'this is what the bug looked like',
    );
  });

  test('a day with no menus published is empty, not an error', () {
    final quiet = {
      'service_date': '2026-08-30',
      'locations': [
        {'id': 23, 'name': 'Crossroads', 'menus': <dynamic>[]},
      ],
    };
    expect(menuItemsWithCategory(quiet, null), isEmpty);
    expect(menuItemsWithCategory(quiet, visitingChef), isEmpty);
  });
}
