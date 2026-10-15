/// Visiting chefs from rit.edu.
///
/// TigerCenter `dining-all` used to carry visiting chefs in `menus[]`. It now
/// returns 24 locations with every `menus[]` empty, so this reads the two
/// public rit.edu pages that publish the same thing:
///
///  - `/dining/menus`, server rendered. Under the "Today's Visiting Chefs"
///    heading each location is a block with its name, and each chef is an
///    anchor carrying `chefid="<locationId>-<n>"` whose `<em>` reads
///    "Chef: 11:00 am - 2:00 pm". The cuisine sits in
///    `#<chefid>-chef-holder`. The chefid prefix is the TigerCenter location
///    id. This is the only place times are published.
///  - `/dining/visiting-chefs`, fourteen `div.daily-visiting-chefs#day-DATE`
///    blocks. Names only, no times, and the inline `display: none` on every
///    day is a carousel detail that means nothing here. It is matched to a
///    TigerCenter location by name.
///
/// Parsing targets the `chefid` and `-chef-holder` ids and the `day-` ids
/// rather than Bootstrap classes, because ids are what the page's own script
/// relies on. It uses regular expressions like `recreation.dart`, so no HTML
/// parser dependency.
library;

import '../campus_time.dart';
import '../upstream.dart';
import 'recreation.dart' show textOf;
import 'tigercenter.dart';

const String ritChefsSource = 'rit_chefs';
const String ritMenusUrl = 'https://www.rit.edu/dining/menus';
const String ritVisitingChefsUrl = 'https://www.rit.edu/dining/visiting-chefs';

/// Where the card sends someone when nothing could be read.
const String ritDiningPageUrl = ritMenusUrl;

/// The three answers the chefs feed can give. `unavailable` is not `empty`:
/// empty is a real quiet day, unavailable means nobody could say.
const String availabilityAvailable = 'available';
const String availabilityEmpty = 'empty';
const String availabilityUnavailable = 'unavailable';

// --- parsing -----------------------------------------------------------

final RegExp _chefAnchorRe = RegExp(
  r'chefid="(\d+)-(\d+)"[^>]*>\s*<em>(.*?)</em>',
  dotAll: true,
);
final RegExp _locationNameRe = RegExp(
  r'<p class="h5[^"]*">(.*?)</p>',
  dotAll: true,
);

const String _time = r'\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?';
final RegExp _chefTextRe = RegExp(
  '^(.*?)\\s*:\\s*($_time)\\s*[-–—]\\s*($_time)\\s*\$',
  caseSensitive: false,
  dotAll: true,
);

/// '11:00 am' becomes '11:00'. Null when it is not a clock time.
String? _clock(String token) {
  final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([ap])', caseSensitive: false)
      .firstMatch(token.trim());
  if (m == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2) ?? '0');
  final pm = m.group(3)!.toLowerCase() == 'p';
  if (hour < 1 || hour > 12 || minute > 59) return null;
  if (pm && hour != 12) hour += 12;
  if (!pm && hour == 12) hour = 0;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

/// Splits "Chef: 11:00 am - 2:00 pm" on the colon that precedes the time
/// range, so a name that itself holds a colon survives.
({String name, String? start, String? end}) splitChefText(String text) {
  final m = _chefTextRe.firstMatch(text);
  if (m == null) return (name: text.trim(), start: null, end: null);
  final start = _clock(m.group(2)!);
  final end = _clock(m.group(3)!);
  if (start == null || end == null) {
    return (name: text.trim(), start: null, end: null);
  }
  return (name: m.group(1)!.trim(), start: start, end: end);
}

/// What the "Today's Visiting Chefs" block of `/dining/menus` says.
///
/// [found] is false when the heading is not on the page at all, which means
/// the structure changed or the page is not the dining page. That is different
/// from found with no chefs, which is a quiet day.
({bool found, List<Map<String, dynamic>> chefs}) parseTodayChefs(String html) {
  final heading = RegExp(
    r"<h2[^>]*>(?:(?!</h2>).)*Today(?:'|&#0?39;|’)s Visiting Chefs",
    dotAll: true,
  ).firstMatch(html);
  if (heading == null) return (found: false, chefs: const []);

  var end = html.length;
  for (final stop in ['<script', '<h2']) {
    final at = html.indexOf(stop, heading.end);
    if (at != -1 && at < end) end = at;
  }
  final section = html.substring(heading.end, end);

  // The location name is the nearest heading above the anchor. Chef ids carry
  // the location id, so a missing name costs the label and nothing else.
  final names = [
    for (final m in _locationNameRe.allMatches(section))
      (m.start, textOf(m.group(1)!)),
  ];

  final chefs = <Map<String, dynamic>>[];
  for (final m in _chefAnchorRe.allMatches(section)) {
    final locationId = int.parse(m.group(1)!);
    final chefId = '${m.group(1)}-${m.group(2)}';
    final text = splitChefText(textOf(m.group(3)!));

    String? locationName;
    for (final (at, name) in names) {
      if (at < m.start) locationName = name;
    }

    // The popup holds the display name and the cuisine. Its span is
    // preferred because the anchor text is "name: times".
    final holder = RegExp(
      'id="$chefId-chef-holder"(.*?)</div>',
      dotAll: true,
    ).firstMatch(section);
    String? holderName;
    String? cuisine;
    if (holder != null) {
      final body = holder.group(1)!;
      final span = RegExp(r'<span[^>]*>(.*?)</span>', dotAll: true)
          .firstMatch(body);
      final em = RegExp(r'<em[^>]*>(.*?)</em>', dotAll: true).firstMatch(body);
      if (span != null) holderName = textOf(span.group(1)!);
      if (em != null) cuisine = textOf(em.group(1)!);
    }

    final name = (holderName?.isNotEmpty ?? false) ? holderName! : text.name;
    if (name.isEmpty) continue;
    chefs.add({
      'chef_id': chefId,
      'location_id': locationId,
      'location_name': locationName,
      'name': name,
      'cuisine': (cuisine?.isEmpty ?? true) ? null : cuisine,
      'start': text.start,
      'end': text.end,
    });
  }
  if (chefs.isNotEmpty) return (found: true, chefs: chefs);

  // No chefs. The heading alone proves nothing: a page that keeps it and
  // restructures everything under it looks exactly like this. A quiet day
  // needs positive evidence, and chef markup that is present but did not
  // match is the page changing under the parser, never a quiet day.
  if (section.contains('chefid') || section.contains('<li')) {
    return (found: false, chefs: const []);
  }
  return (found: _confirmsNoChefs(section), chefs: const []);
}

final RegExp _emptyMarkerRe = RegExp(r'class="[^"]*\bno-visiting-chefs\b');

/// A location block exactly as populated days have it: the linked `p.h5`
/// name, then the `ul` that would hold the chefs.
final RegExp _locationBlockRe = RegExp(
  r'<a[^>]*>\s*<p class="h5[^"]*">.*?</p>\s*</a>\s*<ul[^>]*>(.*?)</ul>',
  dotAll: true,
);

/// Whether a section with no chefs says so on purpose: RIT's own
/// `no-visiting-chefs` marker, or at least one location block of the
/// structure populated days use, every one of whose lists is empty.
bool _confirmsNoChefs(String section) {
  if (_emptyMarkerRe.hasMatch(section)) return true;
  final blocks = _locationBlockRe.allMatches(section).toList();
  return blocks.isNotEmpty &&
      blocks.every((b) => b.group(1)!.trim().isEmpty);
}

final RegExp _dayRe = RegExp(
  r'<div[^>]*\bid="day-(\d{4}-\d{2}-\d{2})"[^>]*>',
);

/// Every day on `/dining/visiting-chefs`, keyed by `YYYY-MM-DD`.
///
/// All fourteen are in the markup and the page hides all but one with inline
/// style, so visibility is ignored. A day with `p.no-visiting-chefs` or no
/// chefs is an empty day, which is still a day the page has spoken for.
Map<String, Map<String, dynamic>> parseChefSchedule(String html) {
  final days = <Map<String, dynamic>>[];
  final starts = _dayRe.allMatches(html).toList();
  for (var i = 0; i < starts.length; i++) {
    var end = i + 1 < starts.length ? starts[i + 1].start : html.length;
    // The last day runs into the buttons, scripts and the carousel.
    for (final stop in ['id="prev-chef"', '<script', '<h2']) {
      final at = html.indexOf(stop, starts[i].end);
      if (at != -1 && at < end) end = at;
    }
    days.add({'date': starts[i].group(1)!, 'html': html.substring(starts[i].end, end)});
  }

  final out = <String, Map<String, dynamic>>{};
  for (final day in days) {
    final body = day['html'] as String;
    final chefs = <Map<String, dynamic>>[];
    for (final block in RegExp(
      r'<span>(.*?)</span>\s*<ul[^>]*>(.*?)</ul>',
      dotAll: true,
    ).allMatches(body)) {
      final location = textOf(block.group(1)!);
      for (final li in RegExp(r'<li[^>]*>\s*<em>(.*?)</em>', dotAll: true)
          .allMatches(block.group(2)!)) {
        final name = textOf(li.group(1)!);
        if (name.isNotEmpty) chefs.add({'name': name, 'location_name': location});
      }
    }
    // Empty is only ever what the page says, `p.no-visiting-chefs`. A day with
    // neither that marker nor a parsed chef is a block the parser could not
    // read, and it is kept as `unknown` so it cannot confirm a quiet day.
    final marked = RegExp(r'class="[^"]*\bno-visiting-chefs\b').hasMatch(body);
    out[day['date'] as String] = {
      'empty': chefs.isEmpty && marked,
      'unknown': chefs.isEmpty && !marked,
      'chefs': chefs,
    };
  }
  return out;
}

// --- scrape ------------------------------------------------------------

/// Both pages, each tolerated failing on its own. Whichever part fails keeps
/// the previous snapshot's copy, so cached chefs still show, but is marked
/// failed (`today_ok`, `schedule_ok`) so that copy cannot confirm a quiet day.
/// `today_at` and `schedule_at` are when each part last really succeeded,
/// which needs a page that parsed, not just an HTTP 200.
///
/// Never throws: a total failure is recorded in the snapshot too, because
/// leaving the old snapshot untouched would leave its "ok" flags standing.
Future<Map<String, dynamic>> scrapeRitChefs(
  Upstream http, {
  Map<String, dynamic>? previous,
}) async {
  final now = CampusTime.nowUtc();
  final today = CampusTime.formatDate(now);
  Map<String, dynamic>? todayPart = previous?['today'] as Map<String, dynamic>?;
  Map<String, dynamic>? schedule = previous?['schedule'] as Map<String, dynamic>?;
  var todayAt = previous?['today_at'];
  var scheduleAt = previous?['schedule_at'];
  var todayOk = false;
  var scheduleOk = false;

  try {
    final parsed = parseTodayChefs(await http.getText(ritMenusUrl));
    // A 200 is not a read. Only a page whose chef block was recognised, with
    // chefs or as an empty block, counts. Anything else keeps the previous
    // copy and time, and is flagged failed like a network error, so it is
    // retried after five minutes and never advances "last updated".
    if (parsed.found) {
      todayPart = {'date': today, 'found': true, 'chefs': parsed.chefs};
      todayAt = CampusTime.format(now);
      todayOk = true;
    }
  } on UpstreamError {
    // Kept as previous, flagged failed below.
  }
  try {
    final parsed = parseChefSchedule(await http.getText(ritVisitingChefsUrl));
    // Usable means at least one day was read as chefs or an explicit empty.
    if (parsed.values.any((day) => day['unknown'] != true)) {
      schedule = parsed;
      scheduleAt = CampusTime.format(now);
      scheduleOk = true;
    }
  } on UpstreamError {
    // Kept as previous, flagged failed below.
  }

  return {
    'service_date': today,
    'today': todayPart,
    'schedule': schedule,
    'today_ok': todayOk,
    'schedule_ok': scheduleOk,
    'today_at': todayAt,
    'schedule_at': scheduleAt,
  };
}

/// Whether this snapshot is not a clean read of both pages: the last attempt
/// failed, or it predates the `*_ok` fields. Such a snapshot is retried after
/// five minutes instead of thirty, and pull to refresh waits the same five.
bool ritChefsFailed(Map<String, dynamic> snapshot) =>
    snapshot['today_ok'] != true || snapshot['schedule_ok'] != true;

DateTime? _stamp(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// When this feed last held real chef information. A TigerCenter snapshot
/// whose every `menus[]` is empty is not that, so a first run outage reports
/// null rather than the moment the failed fetch happened.
DateTime? chefsLastUpdated({
  required Map<String, dynamic>? tigerCenter,
  required DateTime? tigerCenterAt,
  required Map<String, dynamic>? rit,
  required DateTime now,
}) {
  final stamps = <DateTime>[
    ?_stamp(rit?['today_at']),
    ?_stamp(rit?['schedule_at']),
    if (tigerCenterAt != null &&
        tigerCenter?['service_date'] == CampusTime.formatDate(now) &&
        !tigerCenterMenusEmpty(tigerCenter))
      tigerCenterAt.toUtc(),
  ]..sort();
  return stamps.isEmpty ? null : stamps.last;
}

// --- projection --------------------------------------------------------

/// Lower case, ampersand as "and", letters and digits only, no leading "the".
/// The visiting chefs page matches locations by name alone.
String normalizeLocationName(String name) {
  var value = name.toLowerCase().replaceAll('&', ' and ');
  value = value.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value.startsWith('the ') ? value.substring(4) : value;
}

String? _isoOn(String date, String? clock) {
  if (clock == null) return null;
  final d = date.split('-').map(int.parse).toList();
  final c = clock.split(':').map(int.parse).toList();
  return CampusTime.format(CampusTime.wall(d[0], d[1], d[2], c[0], c[1]));
}

/// Whether TigerCenter is serving menus at all. Every location empty is the
/// outage signature (24 of 24 on 2026-10-14), and a missing snapshot is no
/// better.
bool tigerCenterMenusEmpty(Map<String, dynamic>? snapshot) {
  final locations = snapshot?['locations'] as List<dynamic>? ?? const [];
  for (final raw in locations) {
    final menus = (raw as Map<String, dynamic>)['menus'] as List<dynamic>?;
    if (menus != null && menus.isNotEmpty) return false;
  }
  return true;
}

/// Today's visiting chefs from both sources, and how sure we are.
///
///  - **available**: at least one chef.
///  - **empty**: a source whose last read succeeded says there are none, by an
///    explicit marker or a parsed page.
///  - **unavailable**: nothing that is currently working can say. TigerCenter
///    has no menus for today, and rit.edu is unread, unreadable, failed on its
///    last attempt, or from another day. Showing "no visiting chefs" there
///    would be a guess.
///
/// rit.edu `/dining/menus` wins for today because it has the times. The
/// schedule page fills in when that block is missing or empty, and TigerCenter
/// adds chefs the others do not already list, so the feed keeps working if it
/// ever publishes again.
Map<String, dynamic> visitingChefsView({
  required Map<String, dynamic>? tigerCenter,
  required Map<String, dynamic>? rit,
  required DateTime now,
}) {
  final today = CampusTime.formatDate(now);

  final locationIds = <String, int>{};
  for (final raw in tigerCenter?['locations'] as List<dynamic>? ?? const []) {
    final loc = raw as Map<String, dynamic>;
    locationIds[normalizeLocationName(loc['name'] as String? ?? '')] =
        loc['id'] as int;
  }

  final menusPart = rit?['today'] as Map<String, dynamic>?;
  // Cached chefs keep showing whatever happened since, but only a source
  // whose last attempt succeeded may say "none today".
  final menusToday = menusPart != null &&
      menusPart['date'] == today &&
      menusPart['found'] == true;
  //
  // Confirmation is opt in: snapshots stored before these fields existed lack
  // them, and one of those once marked an unparsed day as empty. They still
  // show their chefs, and `ritChefsFailed` has them refetched.
  final menusConfirms = menusToday && rit?['today_ok'] == true;
  final schedule = rit?['schedule'] as Map<String, dynamic>?;
  var scheduleToday = schedule?[today] as Map<String, dynamic>?;
  // A day block the parser could not read says nothing, either way.
  if (scheduleToday?['unknown'] == true) scheduleToday = null;
  final scheduleConfirms =
      scheduleToday != null &&
      scheduleToday['unknown'] == false &&
      rit?['schedule_ok'] == true;

  // TigerCenter's snapshot is a day's payload. Yesterday's chef is not today's.
  final tcToday = tigerCenter?['service_date'] == today ? tigerCenter : null;

  final items = <Map<String, dynamic>>[];
  var nextId = 1000000;
  void add(Map<String, dynamic> item) =>
      items.add({'id': nextId++, 'service_date': today, ...item});

  final fromMenus = menusToday
      ? (menusPart['chefs'] as List<dynamic>).cast<Map<String, dynamic>>()
      : const <Map<String, dynamic>>[];
  for (final c in fromMenus) {
    add({
      'location_id': c['location_id'],
      'location_name': c['location_name'] ?? '',
      'name': c['name'],
      'description': null,
      'price': null,
      'category': visitingChef,
      'cuisine': c['cuisine'],
      'start_time': _isoOn(today, c['start'] as String?),
      'end_time': _isoOn(today, c['end'] as String?),
    });
  }

  if (fromMenus.isEmpty && scheduleToday != null) {
    for (final c in (scheduleToday['chefs'] as List<dynamic>)
        .cast<Map<String, dynamic>>()) {
      final name = c['location_name'] as String;
      add({
        'location_id': locationIds[normalizeLocationName(name)],
        'location_name': name,
        'name': c['name'],
        'description': null,
        'price': null,
        'category': visitingChef,
        'cuisine': null,
        'start_time': null,
        'end_time': null,
      });
    }
  }

  String key(Object? locationId, Object? locationName, Object? chef) =>
      '${locationId ?? normalizeLocationName('$locationName')}|'
      '${normalizeLocationName('$chef')}';
  final seen = {
    for (final i in items) key(i['location_id'], i['location_name'], i['name']),
  };
  for (final tc in menuItemsWithCategory(tcToday ?? const {}, visitingChef)) {
    if (!seen.add(key(tc['location_id'], tc['location_name'], tc['name']))) {
      continue;
    }
    add({...tc, 'cuisine': null, 'start_time': null, 'end_time': null});
  }

  if (items.isNotEmpty) {
    return {'items': items, 'availability': availabilityAvailable};
  }

  if (!tigerCenterMenusEmpty(tcToday) || menusConfirms || scheduleConfirms) {
    return {
      'items': items,
      'availability': availabilityEmpty,
      'next': _nextChef(schedule, today),
    };
  }
  return {'items': items, 'availability': availabilityUnavailable};
}

Map<String, dynamic>? _nextChef(Map<String, dynamic>? schedule, String today) {
  if (schedule == null) return null;
  for (final date in schedule.keys.toList()..sort()) {
    if (date.compareTo(today) <= 0) continue;
    final chefs = (schedule[date] as Map<String, dynamic>)['chefs'] as List;
    if (chefs.isEmpty) continue;
    final first = chefs.first as Map<String, dynamic>;
    return {
      'date': date,
      'name': first['name'],
      'location_name': first['location_name'],
    };
  }
  return null;
}
