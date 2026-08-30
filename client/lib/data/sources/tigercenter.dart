/// TigerCenter dining: locations, hours, visiting chefs.
///
/// Ported from `backend/app/scrapers/tigercenter.py`.
///
/// Endpoint: https://tigercenter.rit.edu/tigerCenterApi/tc/dining-all?date=YYYY-MM-DD
/// No auth, no cookies, no custom headers. Verified 2026-08-28.
///
/// Everything under the TCAuth base (/tigerCenterApi/login_shib/tc/) is login
/// gated and is deliberately never touched.
///
/// This one payload carries three things: location metadata, the hours
/// recurrence model, and `menus[]` where category == "Visiting Chef".
///
/// The raw `events` are kept in the snapshot rather than resolved at scrape
/// time, because "is it open right now" has to be answered against the moment
/// the user is looking, not the moment the scrape ran.
library;

import '../campus_time.dart';
import '../hours.dart';
import '../static_config.dart';
import '../upstream.dart';

const String tigerCenterUrl =
    'https://tigercenter.rit.edu/tigerCenterApi/tc/dining-all';

/// How far ahead to resolve concrete hours. Two weeks covers the calendar view
/// without bloating the snapshot.
const int diningHorizonDays = 14;

const String visitingChef = 'Visiting Chef';

List<Map<String, dynamic>> parseDining(Map<String, dynamic> payload) => [
      for (final raw in payload['locations'] as List<dynamic>? ?? const [])
        if (raw is Map<String, dynamic>)
          {
            'id': raw['id'],
            'name': raw['name'] ?? '',
            'summary': raw['summary'],
            'description': raw['description'],
            'maps_url': raw['mapsUrl'],
            'department': raw['department'],
            'mdo_id': raw['mdoId'],
            'events': raw['events'] ?? const [],
            'menus': raw['menus'] ?? const [],
          },
    ];

Future<Map<String, dynamic>> scrapeDining(Upstream http) async {
  final today = CampusTime.formatDate(CampusTime.nowUtc());
  final payload =
      await http.getJson('$tigerCenterUrl?date=$today') as Map<String, dynamic>;

  final locations = parseDining(payload);
  if (locations.isEmpty) {
    throw UpstreamError('dining-all returned zero locations');
  }

  return {'service_date': today, 'locations': locations};
}

// --- projections -------------------------------------------------------
//
// The backend resolved these in `api/dining.py`. They run at read time here,
// against the moment the user is looking.

/// Occupancy is optional by design. A missing reading hides the chip.
///
/// A reading with a count but no usable denominator still returns a chip, with
/// percent_full left null. The client shows the raw count rather than silently
/// dropping the location, so a missing capacity is visible instead of papered
/// over. Verified 2026-08-28: all five sensor locations do publish max_occ, so
/// this is a guard, not the normal path.
Map<String, dynamic>? occupancyFor(Map<String, dynamic>? reading) {
  if (reading == null) return null;
  final count = reading['count'] as int?;
  if (count == null) return null;

  final maxOcc = reading['max_occ'] as int?;
  final denominator = maxOcc ?? 0;
  final percent =
      denominator > 0 ? (100 * count / denominator).round() : null;

  return {
    'count': count,
    'max_occ': maxOcc,
    'open_status': reading['open_status'],
    'percent_full': percent == null ? null : (percent > 100 ? 100 : percent),
    'over_capacity': denominator > 0 && count > denominator,
  };
}

Map<String, dynamic> buildDiningLocation(
  Map<String, dynamic> location,
  DateTime now,
  StaticConfig config,
  Map<String, dynamic>? reading,
) {
  final today = CampusTime.dateOf(now);
  final spans = <Span>[];
  for (var offset = -1; offset < diningHorizonDays; offset++) {
    spans.addAll(resolveDay(
      location['events'] as List<dynamic>? ?? const [],
      today.add(Duration(days: offset)),
    ));
  }

  final state = openState(groupByDate(spans), now);
  final id = location['id'] as int;
  final category = config.categoryFor(id);

  return {
    'id': id,
    'name': location['name'],
    'category': category,
    'category_name': config.categoryName(category),
    'category_order': config.categoryOrder(category),
    'summary': location['summary'],
    'description': location['description'],
    'maps_url': location['maps_url'],
    'mdo_id': location['mdo_id'],
    'is_open': state.isOpen,
    'opens_at': state.opensAt == null ? null : CampusTime.format(state.opensAt!),
    'closes_at':
        state.closesAt == null ? null : CampusTime.format(state.closesAt!),
    'next_transition': state.nextTransition == null
        ? null
        : CampusTime.format(state.nextTransition!),
    'today': [
      for (final s in state.spansToday)
        {
          'opens_at': CampusTime.format(s.startInstant()),
          'closes_at': CampusTime.format(s.endInstant()),
          'is_exception': s.isException,
          'menu_types': s.menuTypes,
        },
    ],
    'occupancy': occupancyFor(reading),
  };
}

/// Visiting chefs and specials both come free from this payload, so no scrape
/// of rit.edu/dining/menus is needed (CLAUDE.md 7.2).
List<Map<String, dynamic>> menuItemsWithCategory(
  Map<String, dynamic> snapshot,
  String category,
) {
  final out = <Map<String, dynamic>>[];
  for (final raw in snapshot['locations'] as List<dynamic>? ?? const []) {
    final location = raw as Map<String, dynamic>;
    for (final item in location['menus'] as List<dynamic>? ?? const []) {
      if (item is! Map<String, dynamic>) continue;
      if (item['category'] != category) continue;
      out.add({
        'id': item['id'],
        'location_id': location['id'],
        'location_name': location['name'],
        'service_date': snapshot['service_date'],
        'name': item['name'],
        'description': item['description'],
        'price': item['price'],
        'category': item['category'],
      });
    }
  }
  return out;
}
