/// Food trucks from rit.edu/dining/food-trucks, with the Drupal Rodeo events as fallback.
library;

import 'package:flutter/foundation.dart';

import '../campus_time.dart';
import '../upstream.dart';
import 'drupal_events.dart';
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

DateTime _shiftMonths(DateTime d, int months) {
  final index = d.year * 12 + d.month - 1 + months;
  final year = index ~/ 12;
  final month = index % 12 + 1;
  final last = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, d.day > last ? last : d.day);
}

// nearest occurrence within 6 months either side, both ends inclusive
// a tie in days goes to the future one, null when nothing is in the window
DateTime? inferTruckDate(int month, int day, DateTime campusDate) {
  final today = DateTime.utc(campusDate.year, campusDate.month, campusDate.day);
  final from = _shiftMonths(today, -6);
  final to = _shiftMonths(today, 6);
  DateTime? best;
  for (final year in [today.year - 1, today.year, today.year + 1]) {
    final candidate = DateTime.utc(year, month, day);
    if (candidate.month != month) continue;
    if (candidate.isBefore(from) || candidate.isAfter(to)) continue;
    if (best == null) {
      best = candidate;
      continue;
    }
    final gap = candidate.difference(today).abs();
    final bestGap = best.difference(today).abs();
    if (gap < bestGap || (gap == bestGap && candidate.isAfter(best))) {
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

final RegExp _hiddenRe = RegExp(r'display\s*:\s*none', caseSensitive: false);
final RegExp _noTrucksRe = RegExp(r'^no\b.*(truck|schedul)', caseSensitive: false);

const String _wrapperClass = 'paragraph--type--embed-view';

// the only elements an empty schedule is allowed to contain
const Set<String> _plainTags = {
  'div', 'span', 'p', 'section', 'article', 'ul', 'ol', 'li', 'br',
  'strong', 'em', 'b', 'i', 'small',
};
const Set<String> _rawTextTags = {'script', 'style'};

final RegExp _tagNameRe = RegExp(r'[a-zA-Z][a-zA-Z0-9:-]*');
final RegExp _attrNameRe = RegExp(r'''[^\s=/>"'<`]+''');
final RegExp _unquotedRe = RegExp(r'''[^\s>"'<=`]+''');

bool _space(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';

// attributes of one start tag, first occurrence of a name wins, null if unreadable
(int, Map<String, String>)? _readTag(String s, int from) {
  final attrs = <String, String>{};
  var j = from;
  while (true) {
    while (j < s.length && _space(s[j])) {
      j++;
    }
    if (j >= s.length) return null;
    if (s[j] == '>') return (j + 1, attrs);
    if (s[j] == '/') return j + 1 < s.length && s[j + 1] == '>' ? (j + 2, attrs) : null;

    final name = _attrNameRe.matchAsPrefix(s, j);
    if (name == null) return null;
    j = name.end;

    var k = j;
    while (k < s.length && _space(s[k])) {
      k++;
    }
    var value = '';
    if (k < s.length && s[k] == '=') {
      k++;
      while (k < s.length && _space(s[k])) {
        k++;
      }
      if (k >= s.length) return null;
      if (s[k] == '"' || s[k] == "'") {
        final close = s.indexOf(s[k], k + 1);
        if (close < 0) return null;
        value = s.substring(k + 1, close);
        j = close + 1;
      } else {
        final bare = _unquotedRe.matchAsPrefix(s, k);
        if (bare == null) return null;
        value = bare.group(0)!;
        j = bare.end;
      }
    }
    attrs.putIfAbsent(name.group(0)!.toLowerCase(), () => value);
  }
}

// empty only when everything is understood: a real, closed view wrapper, no slot
// markers, and no visible text bar a short "no ..." note. anything the scanner
// does not understand counts as not empty, which sends the page to the fallback.
bool isEmptySchedule(String schedule, bool sawSlotMarkers) {
  if (sawSlotMarkers) return false;

  final lower = schedule.toLowerCase();
  final text = StringBuffer();
  final open = <String>[];
  var wrapperSeen = false;
  var wrapperDone = false;
  var i = 0;

  while (i < schedule.length) {
    final lt = schedule.indexOf('<', i);
    text.write(schedule.substring(i, lt < 0 ? schedule.length : lt));
    if (lt < 0) break;
    i = lt;

    if (schedule.startsWith('<!--', i)) {
      final close = schedule.indexOf('-->', i + 4);
      if (close < 0) return false;
      i = close + 3;
      continue;
    }

    if (schedule.startsWith('</', i)) {
      final name = _tagNameRe.matchAsPrefix(schedule, i + 2);
      if (name == null) return false;
      var j = name.end;
      while (j < schedule.length && _space(schedule[j])) {
        j++;
      }
      if (j >= schedule.length || schedule[j] != '>') return false;
      final tag = name.group(0)!.toLowerCase();
      if (!_plainTags.contains(tag)) return false;
      if (open.isNotEmpty) {
        if (open.last != tag) return false;
        open.removeLast();
        if (open.isEmpty) wrapperDone = true;
      }
      i = j + 1;
      continue;
    }

    final name = _tagNameRe.matchAsPrefix(schedule, i + 1);
    if (name == null) return false;
    final tag = name.group(0)!.toLowerCase();
    final read = _readTag(schedule, name.end);
    if (read == null) return false;
    final (after, attrs) = read;

    if (_rawTextTags.contains(tag)) {
      final close = lower.indexOf('</$tag', after);
      if (close < 0) return false;
      final end = schedule.indexOf('>', close);
      if (end < 0) return false;
      i = end + 1;
      continue;
    }
    if (!_plainTags.contains(tag)) return false;
    i = after;
    if (tag == 'br') continue;

    if (wrapperSeen && !wrapperDone) {
      open.add(tag);
    } else if (!wrapperSeen && (attrs['class'] ?? '').split(RegExp(r'\s+')).contains(_wrapperClass)) {
      wrapperSeen = true;
      open.add(tag);
    }
  }

  if (!wrapperSeen || !wrapperDone) return false;
  final visible = textOf(text.toString());
  if (visible.isEmpty) return true;
  return visible.length <= 120 && _noTrucksRe.hasMatch(visible);
}

// null means the page structure is not what we expect
Map<String, dynamic>? parseFoodTrucksHtml(String html, DateTime campusDate) {
  final heading = _headingRe.firstMatch(html);
  if (heading == null || !html.contains('id="current-schedule"')) return null;

  final rosterAt = html.indexOf(_rosterAnchorRe, heading.end);
  final schedule = html.substring(
    heading.end,
    // stop before the anchor tag itself, not halfway through it
    rosterAt < 0 ? html.length : html.lastIndexOf('<', rosterAt),
  );

  final marks = _dateRe.allMatches(schedule).toList();
  final trucks = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (var i = 0; i < marks.length; i++) {
    final end = i + 1 < marks.length ? marks[i + 1].start : schedule.length;
    final block = schedule.substring(marks[i].end, end);

    final before = schedule.substring(i == 0 ? 0 : marks[i - 1].end, marks[i].start);
    final column = before.lastIndexOf('<div class="col-');
    if (column >= 0) {
      final tag = before.substring(column, before.indexOf('>', column) + 1);
      if (_hiddenRe.hasMatch(tag)) continue;
    }

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

    final location = place == null ? null : _clean(place.group(3));
    if (!seen.add('$name|${_ymd(day)}|$timeText|$location')) continue;

    trucks.add({
      'name': name,
      'blurb': _clean(_blurbRe.firstMatch(afterName)?.group(1)),
      'date': _ymd(day),
      'time_text': timeText,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'location': location,
      'location_url': place?.group(1),
      'website': _siteRe.firstMatch(block)?.group(1),
      'origin': 'html',
    });
  }

  // empty needs positive evidence, anything unreadable is a changed page
  if (trucks.isEmpty && !isEmptySchedule(schedule, marks.isNotEmpty)) return null;

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
    final date = CampusTime.formatDate(startsAt);
    if (date.compareTo(_ymd(campusDate)) < 0) continue;
    out.add({
      'name': 'Food Truck Rodeo',
      'blurb': null,
      'date': date,
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

// spacing for every fetch, scheduled or manual: 6 hours after a clean read,
// 5 minutes after anything else. a clean read is stored with its fetched_at
// so a restart keeps the spacing, failures are only remembered in memory.
class FoodTruckPacer {
  FoodTruckPacer({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _attemptAt;
  bool _clean = true;

  DateTime now() => _clock();

  bool due(Map<String, dynamic>? previous) {
    var at = _attemptAt;
    var clean = _clean;
    final stored = DateTime.tryParse(previous?['fetched_at'] as String? ?? '');
    if (stored != null && (at == null || stored.isAfter(at))) {
      at = stored;
      clean = previous?['origin'] == 'html';
    }
    if (at == null) return true;
    return _clock().difference(at) >= (clean ? foodTrucksCadence : foodTruckRetry);
  }

  void record({required bool clean}) {
    _attemptAt = _clock();
    _clean = clean;
  }

  @visibleForTesting
  void reset() {
    _attemptAt = null;
    _clean = true;
  }
}

const Duration foodTruckRetry = Duration(minutes: 5);

final FoodTruckPacer foodTruckPacer = FoodTruckPacer();

// cached drupal events first, then one small title filtered fetch
Future<List<Map<String, dynamic>>> _rodeoTrucks(
  Upstream http,
  Future<Map<String, dynamic>?> Function() drupalSnapshot,
  DateTime campusDate,
) async {
  final cached = rodeoTrucksFrom(await drupalSnapshot(), campusDate);
  if (cached.isNotEmpty) return cached;
  final records = await fetchDrupal(http, title: rodeoTitle);
  return rodeoTrucksFrom({'events': parseDrupal(records)}, campusDate);
}

// stored unavailable only when both sources were read and neither had trucks
// a fetch error on either side rethrows so the previous snapshot stays
Future<Map<String, dynamic>> scrapeFoodTrucks(
  Upstream http,
  Future<Map<String, dynamic>?> Function() drupalSnapshot, {
  Map<String, dynamic>? previous,
  FoodTruckPacer? pacer,
}) async {
  final gate = pacer ?? foodTruckPacer;
  if (!gate.due(previous)) throw UpstreamError('food_trucks: not due yet');

  final campusDate = CampusTime.wallDate();
  Map<String, dynamic> stamped(Map<String, dynamic> body) => {
    ...body,
    'fetched_at': gate.now().toUtc().toIso8601String(),
  };

  var primaryFetchFailed = false;
  Map<String, dynamic>? parsed;
  try {
    final html = await http.getText(foodTrucksUrl);
    try {
      parsed = parseFoodTrucksHtml(html, campusDate);
    } catch (error) {
      debugPrint('food_trucks: parser threw $error');
    }
  } catch (error) {
    primaryFetchFailed = true;
    debugPrint('food_trucks: page fetch failed: $error');
  }

  if (parsed != null) {
    gate.record(clean: true);
    return stamped(parsed);
  }
  if (!primaryFetchFailed) {
    debugPrint('food_trucks: page structure not recognised, trying drupal');
  }

  var fallbackFetchFailed = false;
  var rodeo = <Map<String, dynamic>>[];
  try {
    rodeo = await _rodeoTrucks(http, drupalSnapshot, campusDate);
  } catch (error) {
    fallbackFetchFailed = true;
    debugPrint('food_trucks: drupal fallback fetch failed: $error');
  }
  gate.record(clean: false);

  if (rodeo.isNotEmpty) {
    return stamped({
      'trucks': rodeo,
      'roster': <Map<String, dynamic>>[],
      'season_months': defaultFoodTruckSeasonMonths.toList()..sort(),
      'origin': 'drupal',
    });
  }
  if (primaryFetchFailed || fallbackFetchFailed) {
    throw UpstreamError('food_trucks: could not read a source');
  }

  debugPrint('food_trucks: html and drupal fallback both failed, unavailable');
  return stamped(unavailableFoodTrucks());
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
