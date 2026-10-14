/// Food trucks from rit.edu/dining/food-trucks, with the Drupal Rodeo events as fallback.
library;

import 'package:flutter/foundation.dart';

import '../campus_time.dart';
import '../upstream.dart';
import 'recreation.dart' show textOf;

const String foodTrucksSource = 'food_trucks';
const String foodTrucksUrl = 'https://www.rit.edu/dining/food-trucks';
const Duration foodTrucksCadence = Duration(hours: 6);

// server ignores If-None-Match and If-Modified-Since (always 200, etag is a
// per request timestamp), so there is no conditional fetch here

// --- season rule, the one place it lives ---
// the page says "typically August through October and April"
const Set<int> defaultFoodTruckSeasonMonths = {4, 8, 9, 10};

const String rodeoTitle = 'Food Truck Rodeo Schedule';

enum FoodTruckState { trucks, empty, unavailable }

const Map<String, int> _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

int? _monthOf(String name) =>
    name.length < 3 ? null : _months[name.substring(0, 3).toLowerCase()];

final RegExp _seasonRe = RegExp(
  r'typically\s+(\w+)\s+through\s+(\w+)(?:\s+and\s+(\w+))?',
  caseSensitive: false,
);

Set<int> foodTruckSeasonMonths(String? html) {
  final m = html == null ? null : _seasonRe.firstMatch(textOf(html));
  final from = m == null ? null : _monthOf(m.group(1)!);
  final to = m == null ? null : _monthOf(m.group(2)!);
  if (m == null || from == null || to == null) {
    return defaultFoodTruckSeasonMonths;
  }
  final months = <int>{};
  for (var i = from; ; i = i % 12 + 1) {
    months.add(i);
    if (i == to) break;
  }
  final extra = m.group(3) == null ? null : _monthOf(m.group(3)!);
  if (extra != null) months.add(extra);
  return months;
}

bool isFoodTruckSeason(DateTime campusDate, Iterable<int> months) =>
    months.contains(campusDate.month);

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// nearest of last, this and next year to the campus date
DateTime? inferTruckDate(int month, int day, DateTime campusDate) {
  final today = DateTime.utc(campusDate.year, campusDate.month, campusDate.day);
  DateTime? best;
  for (final year in [today.year - 1, today.year, today.year + 1]) {
    final candidate = DateTime.utc(year, month, day);
    if (candidate.month != month) continue;
    if (best == null ||
        candidate.difference(today).abs() < best.difference(today).abs()) {
      best = candidate;
    }
  }
  return best;
}

final RegExp _headingRe = RegExp(
  r'<h2[^>]*>\s*Current Schedule\s*</h2>',
  caseSensitive: false,
);
final RegExp _rosterAnchorRe = RegExp(r'id="all-participating-trucks"');
final RegExp _dateRe = RegExp(
  r'<div class="h5 mb-3">(?:\s*<div[^>]*>[^<]*</div>)?\s*([^<]*?)\s*</div>',
);
final RegExp _slotDateRe = RegExp(r'^\w+,\s*(\w+)\s+(\d{1,2})$');
final RegExp _nameRe = RegExp(
  r'<div class="[^"]*font-weight-medium h4[^"]*">\s*(.*?)\s*</div>',
  dotAll: true,
);
final RegExp _blurbRe = RegExp(
  r'<div class="mb-2">\s*([^<]+?)\s*</div>',
  dotAll: true,
);
final RegExp _timeRe = RegExp(
  r'fa-clock[^>]*></span>(.*?)</div>',
  dotAll: true,
);
final RegExp _placeRe = RegExp(
  r'<a href="(https://maps\.rit\.edu/details/(\d+))"[^>]*>(.*?)</a>',
  dotAll: true,
);
final RegExp _siteRe = RegExp(
  r'<a href="([^"]+)"[^>]*>(?:<span[^>]*></span>)?\s*Visit Website\s*</a>',
  dotAll: true,
);
final RegExp _rosterRe = RegExp(
  r'<article[^>]*food-truck-teaser[^>]*>(.*?)</article>',
  dotAll: true,
);
final RegExp _cardNameRe = RegExp(
  r'<div[^>]*card-title[^>]*>(.*?)</div>',
  dotAll: true,
);
final RegExp _cardBlurbRe = RegExp(
  r'<div class="mt-1 card-text">(.*?)</div>',
  dotAll: true,
);
final RegExp _clockRe = RegExp(
  r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
  caseSensitive: false,
);

int? _hour24(Match m) {
  final hour = int.parse(m.group(1)!);
  if (hour < 1 || hour > 12) return null;
  final pm = m.group(3)!.toLowerCase() == 'pm';
  return hour % 12 + (pm ? 12 : 0);
}

(String?, String?) _span(DateTime day, String text) {
  final clocks = _clockRe.allMatches(text).toList();
  if (clocks.length != 2) return (null, null);
  final stamps = <String>[];
  for (final c in clocks) {
    final hour = _hour24(c);
    if (hour == null) return (null, null);
    final minute = int.tryParse(c.group(2) ?? '0') ?? 0;
    stamps.add(CampusTime.format(
      CampusTime.wall(day.year, day.month, day.day, hour, minute),
    ));
  }
  return (stamps[0], stamps[1]);
}

String? _clean(String? raw) {
  final value = raw == null ? '' : textOf(raw);
  return value.isEmpty ? null : value;
}

// null means the page structure is not what we expect
Map<String, dynamic>? parseFoodTrucksHtml(String html, DateTime campusDate) {
  final heading = _headingRe.firstMatch(html);
  if (heading == null || !html.contains('id="current-schedule"')) return null;

  final rosterAt = html.indexOf(_rosterAnchorRe, heading.end);
  final schedule = html.substring(
    heading.end,
    rosterAt < 0 ? html.length : rosterAt,
  );

  final marks = _dateRe.allMatches(schedule).toList();
  final trucks = <Map<String, dynamic>>[];
  for (var i = 0; i < marks.length; i++) {
    final end = i + 1 < marks.length ? marks[i + 1].start : schedule.length;
    final block = schedule.substring(marks[i].end, end);

    final label = _slotDateRe.firstMatch(textOf(marks[i].group(1)!));
    final month = label == null ? null : _monthOf(label.group(1)!);
    final name = _clean(_nameRe.firstMatch(block)?.group(1));
    if (label == null || month == null || name == null) continue;

    final day = inferTruckDate(month, int.parse(label.group(2)!), campusDate);
    if (day == null) continue;

    final timeText = _clean(_timeRe.firstMatch(block)?.group(1));
    final (startsAt, endsAt) = timeText == null ? (null, null) : _span(day, timeText);
    final place = _placeRe.firstMatch(block);
    // blurb sits between the name and the clock
    final afterName = block.substring(_nameRe.firstMatch(block)!.end);

    trucks.add({
      'name': name,
      'blurb': _clean(_blurbRe.firstMatch(afterName)?.group(1)),
      'date': _ymd(day),
      'time_text': timeText,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'location': place == null ? null : _clean(place.group(3)),
      'location_url': place?.group(1),
      'website': _siteRe.firstMatch(block)?.group(1),
      'origin': 'html',
    });
  }

  // date markers present but none readable is a changed page, not an empty one
  if (marks.isNotEmpty && trucks.isEmpty) return null;

  final roster = <Map<String, dynamic>>[];
  final rosterHtml = rosterAt < 0 ? '' : html.substring(rosterAt);
  for (final card in _rosterRe.allMatches(rosterHtml)) {
    final name = _clean(_cardNameRe.firstMatch(card.group(1)!)?.group(1));
    if (name == null) continue;
    roster.add({
      'name': name,
      'blurb': _clean(_cardBlurbRe.firstMatch(card.group(1)!)?.group(1)),
      'website': _siteRe.firstMatch(card.group(1)!)?.group(1),
    });
  }

  return {
    'trucks': trucks,
    'roster': roster,
    'season_months': foodTruckSeasonMonths(html).toList()..sort(),
    'origin': 'html',
  };
}

// rodeo events from the drupal snapshot, generic title only
List<Map<String, dynamic>> rodeoTrucksFrom(
  Map<String, dynamic>? drupal,
  DateTime campusDate,
) {
  final out = <Map<String, dynamic>>[];
  for (final raw in drupal?['events'] as List<dynamic>? ?? const []) {
    final event = raw as Map<String, dynamic>;
    if (event['title'] != rodeoTitle) continue;
    final startsAt = DateTime.tryParse(event['starts_at'] as String? ?? '');
    if (startsAt == null) continue;
    out.add({
      'name': 'Food Truck Rodeo',
      'blurb': null,
      'date': CampusTime.formatDate(startsAt),
      'time_text': null,
      'starts_at': event['starts_at'],
      'ends_at': event['ends_at'],
      'location': event['location'],
      'location_url': null,
      'website': event['url'],
      'origin': 'drupal',
    });
  }
  return out;
}

Map<String, dynamic> unavailableFoodTrucks() => {
  'trucks': <Map<String, dynamic>>[],
  'roster': <Map<String, dynamic>>[],
  'season_months': defaultFoodTruckSeasonMonths.toList()..sort(),
  'origin': 'none',
};

Future<Map<String, dynamic>> scrapeFoodTrucks(
  Upstream http,
  Future<Map<String, dynamic>?> Function() drupalSnapshot,
) async {
  final campusDate = CampusTime.wallDate();
  // a network error rethrows so the previous snapshot stays
  final html = await http.getText(foodTrucksUrl);

  final parsed = parseFoodTrucksHtml(html, campusDate);
  if (parsed != null) return parsed;
  debugPrint('food_trucks: page structure not recognised, trying drupal');

  final fallback = rodeoTrucksFrom(await drupalSnapshot(), campusDate);
  if (fallback.isNotEmpty) {
    return {
      'trucks': fallback,
      'roster': <Map<String, dynamic>>[],
      'season_months': defaultFoodTruckSeasonMonths.toList()..sort(),
      'origin': 'drupal',
    };
  }

  debugPrint('food_trucks: html and drupal fallback both failed, unavailable');
  return unavailableFoodTrucks();
}

// what the ui reads, computed against the campus date at read time
class FoodTruckView {
  const FoodTruckView({
    required this.state,
    required this.inSeason,
    required this.trucks,
    required this.roster,
    required this.origin,
  });

  final FoodTruckState state;
  final bool inSeason;
  final List<Map<String, dynamic>> trucks;
  final List<Map<String, dynamic>> roster;
  final String origin;

  // empty and off season hides the group, empty and in season shows one line
  bool get hidden => switch (state) {
    FoodTruckState.unavailable => true,
    FoodTruckState.empty => !inSeason,
    FoodTruckState.trucks => false,
  };
}

FoodTruckView foodTruckView(Map<String, dynamic>? snapshot, DateTime campusDate) {
  final months = [
    for (final m in snapshot?['season_months'] as List<dynamic>? ?? const [])
      m as int,
  ];
  final inSeason = isFoodTruckSeason(
    campusDate,
    months.isEmpty ? defaultFoodTruckSeasonMonths : months,
  );
  final origin = snapshot?['origin'] as String? ?? 'none';
  final roster = [
    for (final r in snapshot?['roster'] as List<dynamic>? ?? const [])
      r as Map<String, dynamic>,
  ];

  if (snapshot == null || origin == 'none') {
    return FoodTruckView(
      state: FoodTruckState.unavailable,
      inSeason: inSeason,
      trucks: const [],
      roster: roster,
      origin: 'none',
    );
  }

  final today = _ymd(campusDate);
  final upcoming = [
    for (final t in snapshot['trucks'] as List<dynamic>? ?? const [])
      if (((t as Map<String, dynamic>)['date'] as String).compareTo(today) >= 0)
        t,
  ]..sort(
      (a, b) => ((a['starts_at'] ?? a['date']) as String)
          .compareTo((b['starts_at'] ?? b['date']) as String),
    );

  return FoodTruckView(
    state: upcoming.isEmpty ? FoodTruckState.empty : FoodTruckState.trucks,
    inSeason: inSeason,
    trucks: upcoming,
    roster: roster,
    origin: origin,
  );
}
