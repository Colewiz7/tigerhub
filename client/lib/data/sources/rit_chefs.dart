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

import 'dart:convert';

import 'package:flutter/foundation.dart';

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

/// Chefs commented out of the page are not on the page.
String _withoutComments(String html) =>
    html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

final RegExp _chefIdRe = RegExp(r'chefid="([^"]+)"');
final RegExp _locationNameRe = RegExp(
  r'<p class="h5[^"]*">(.*?)</p>',
  dotAll: true,
);

/// One side of a range: "11", "11am", "11 a.m.", "11:30 AM" or "noon". The
/// meridiem is optional here because "4-7 p.m." writes it once.
const String _clockToken =
    r'(?:\d{1,2}(?::\d{2})?(?:\s*[ap]\.?\s*m\.?)?|noon)';
final RegExp _chefTextRe = RegExp(
  '^(.*?)\\s*:\\s*($_clockToken)\\s*(?:[-–\\u2014]|to)\\s*($_clockToken)\\s*\$',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _clockRe = RegExp(
  r'^(\d{1,2})(?::(\d{2}))?\s*(?:([ap])\.?\s*m\.?)?$',
  caseSensitive: false,
);

/// Hour 1 to 12 and minute, with the meridiem when it was written.
({int hour, int minute, bool? pm})? _clockOf(String token) {
  final t = token.trim().toLowerCase();
  if (t == 'noon') return (hour: 12, minute: 0, pm: true);
  final m = _clockRe.firstMatch(t);
  if (m == null) return null;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2) ?? '0');
  if (hour < 1 || hour > 12 || minute > 59) return null;
  final meridiem = m.group(3);
  return (
    hour: hour,
    minute: minute,
    pm: meridiem == null ? null : meridiem == 'p',
  );
}

int _minutes(({int hour, int minute, bool? pm}) c, bool pm) =>
    (c.hour % 12 + (pm ? 12 : 0)) * 60 + c.minute;

String _hhmm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// '11 a.m.' and '2 p.m.' become ('11:00', '14:00'). Null when either side is
/// not a clock time or neither side says a.m. or p.m.
///
/// A side without a meridiem takes the other side's, unless that would put
/// the start after the end, in which case the start is a.m. and the end p.m.:
/// "4-7 p.m." is 4 PM to 7 PM, "11-2 p.m." is 11 AM to 2 PM.
({String start, String end})? parseTimeRange(String from, String to) {
  final a = _clockOf(from);
  final b = _clockOf(to);
  if (a == null || b == null) return null;
  var startPm = a.pm;
  var endPm = b.pm;
  if (startPm == null && endPm == null) return null;
  if (startPm == null) {
    startPm = endPm!;
    if (_minutes(a, startPm) > _minutes(b, endPm)) {
      if (!endPm) return null;
      startPm = false;
    }
  } else if (endPm == null) {
    endPm = startPm;
    if (_minutes(b, endPm) < _minutes(a, startPm)) {
      if (startPm) return null;
      endPm = true;
    }
  }
  return (start: _hhmm(_minutes(a, startPm)), end: _hhmm(_minutes(b, endPm)));
}

/// Splits "Chef: 11:00 am - 2:00 pm" on the colon that precedes the time
/// range, so a name that itself holds a colon survives.
///
/// A time that cannot be read is still dropped from the name and the chef goes
/// without a time. The anchor text is always "name: times", so the time field
/// starts at the first colon followed by a digit, or failing that ("TBA",
/// "sometime") at the last colon followed by a space.
({String name, String? start, String? end}) splitChefText(String text) {
  final m = _chefTextRe.firstMatch(text);
  final range = m == null ? null : parseTimeRange(m.group(2)!, m.group(3)!);
  if (range != null) {
    return (name: m!.group(1)!.trim(), start: range.start, end: range.end);
  }
  final digit = RegExp(r'^(.*?)\s*:\s*\d', dotAll: true).firstMatch(text);
  final word = RegExp(r'^(.*):\s+\S', dotAll: true).firstMatch(text);
  final name = (digit ?? word)?.group(1)!.trim() ?? '';
  return (name: name.isEmpty ? text.trim() : name, start: null, end: null);
}

/// What the "Today's Visiting Chefs" block of `/dining/menus` says.
///
/// [found] means at least one chef was parsed, and nothing else. No chefs,
/// whether the heading is missing, the markup changed or the day is genuinely
/// quiet, is not found: this page can say who is cooking, never that nobody is.
///
/// Each chef is read on its own, so one entry that cannot be read is counted
/// in [skipped] and the rest still come through. [untimed] counts chefs kept
/// without a time. [reason] says why nothing was found.
({
  bool found,
  List<Map<String, dynamic>> chefs,
  int skipped,
  int untimed,
  String? reason,
}) parseTodayChefs(String source) {
  final html = _withoutComments(source);
  final heading = RegExp(
    r"<h2[^>]*>(?:(?!</h2>).)*Today(?:'|&#0?39;|’)s Visiting Chefs",
    dotAll: true,
  ).firstMatch(html);
  if (heading == null) {
    return (
      found: false,
      chefs: const [],
      skipped: 0,
      untimed: 0,
      reason: 'no heading',
    );
  }

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
  var skipped = 0;
  var untimed = 0;
  final ids = _chefIdRe.allMatches(section).toList();
  for (var i = 0; i < ids.length; i++) {
    final m = ids[i];
    final chefId = m.group(1)!;
    // The chefid prefix is the TigerCenter location id. An id that is not one
    // costs the id and nothing else; the projection matches the name instead.
    final locationId = int.tryParse(chefId.split('-').first);

    // The anchor's own text, before the next chef starts.
    final end = i + 1 < ids.length ? ids[i + 1].start : section.length;
    final anchor = RegExp(r'^[^>]*>\s*<em[^>]*>(.*?)</em>', dotAll: true)
        .firstMatch(section.substring(m.end, end));
    final text = splitChefText(anchor == null ? '' : textOf(anchor.group(1)!));

    String? locationName;
    for (final (at, name) in names) {
      if (at < m.start) locationName = name;
    }

    // The popup holds the display name and the cuisine. Its span is
    // preferred because the anchor text is "name: times".
    final holder = RegExp(
      'id="${RegExp.escape(chefId)}-chef-holder"(.*?)</div>',
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
    if (name.isEmpty) {
      skipped++;
      continue;
    }
    if (text.start == null) untimed++;
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
  // Zero chefs is unknown, whatever the page looks like around the heading.
  // This page is never read as a quiet day: a changed layout, a comment, a
  // bare heading and a real quiet day all look alike from here, so only the
  // schedule page may say "none today".
  return (
    found: chefs.isNotEmpty,
    chefs: chefs,
    skipped: skipped,
    untimed: untimed,
    reason: chefs.isNotEmpty
        ? null
        : ids.isEmpty
        ? 'no chef entries'
        : 'no entry readable',
  );
}

final RegExp _dayRe = RegExp(
  r'<div[^>]*\bid="day-(\d{4}-\d{2}-\d{2})"[^>]*>',
);

/// Every day on `/dining/visiting-chefs`, keyed by `YYYY-MM-DD`.
///
/// All fourteen are in the markup and the page hides all but one with inline
/// style, so visibility is ignored. A day with `p.no-visiting-chefs` or no
/// chefs is an empty day, which is still a day the page has spoken for.
Map<String, Map<String, dynamic>> parseChefSchedule(String source) {
  final html = _withoutComments(source);
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
/// which needs a page that parsed, not just an HTTP 200. `diagnostics` says
/// what each page returned and how it parsed.
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
  final at = CampusTime.format(now);
  Map<String, dynamic> menusReport;
  Map<String, dynamic> scheduleReport;

  // Anything thrown, a parser bug included, costs that page and is recorded,
  // so the other page and the previous copy still stand.
  ({String text, int status, int bytes})? page;
  try {
    page = await _fetchPage(http, ritMenusUrl);
    final parsed = parseTodayChefs(page.text);
    menusReport = {
      'at': at,
      'status': page.status,
      'bytes': page.bytes,
      'parsed': parsed.chefs.length,
      'skipped': parsed.skipped,
      'untimed': parsed.untimed,
      'reason': parsed.reason,
    };
    // A 200 is not a read. Only a page that yielded chefs counts. Anything
    // else, including a real quiet day, keeps the previous copy and time and
    // is flagged failed like a network error, so it is retried after five
    // minutes and never advances "last updated".
    if (parsed.found) {
      todayPart = {'date': today, 'found': true, 'chefs': parsed.chefs};
      todayAt = at;
      todayOk = true;
    }
  } catch (error) {
    menusReport = _failureReport(at, error, page);
  }
  page = null;
  try {
    page = await _fetchPage(http, ritVisitingChefsUrl);
    final parsed = parseChefSchedule(page.text);
    // Usable means today's own block was read, as chefs or an explicit
    // empty. Another day parsing says nothing about today, so it neither
    // replaces the snapshot nor advances "last updated".
    final todayBlock = parsed[today];
    scheduleReport = {
      'at': at,
      'status': page.status,
      'bytes': page.bytes,
      'parsed': (todayBlock?['chefs'] as List<dynamic>?)?.length ?? 0,
      'reason': todayBlock == null
          ? 'today missing'
          : todayBlock['unknown'] == true
          ? 'today unreadable'
          : null,
    };
    if (todayBlock != null && todayBlock['unknown'] != true) {
      schedule = parsed;
      scheduleAt = at;
      scheduleOk = true;
    }
  } catch (error) {
    scheduleReport = _failureReport(at, error, page);
  }

  final diagnostics = {'menus': menusReport, 'schedule': scheduleReport};
  chefsDiagnostics.value = diagnostics;
  if (!todayOk || (menusReport['skipped'] as int? ?? 0) > 0) {
    debugPrint('rit_chefs: ${chefsDiagnosticsLines(diagnostics).first}');
  }

  return {
    'service_date': today,
    'today': todayPart,
    'schedule': schedule,
    'today_ok': todayOk,
    'schedule_ok': scheduleOk,
    'today_at': todayAt,
    'schedule_at': scheduleAt,
    'diagnostics': diagnostics,
  };
}

/// rit.edu sends UTF-8. `Response.body` throws on a single bad byte, which
/// used to take the whole scrape down with it, so the bytes are decoded here
/// with the bad ones replaced.
Future<({String text, int status, int bytes})> _fetchPage(
  Upstream http,
  String url,
) async {
  final response = await http.request('GET', url);
  return (
    text: utf8.decode(response.bodyBytes, allowMalformed: true),
    status: response.statusCode,
    bytes: response.bodyBytes.length,
  );
}

/// A failed page: status, error type, bytes received and how far parsing got.
/// [page] is set when the fetch worked and the parser threw. No URL and no
/// body, so the report is safe to copy anywhere.
Map<String, dynamic> _failureReport(
  String at,
  Object error,
  ({String text, int status, int bytes})? page,
) {
  final upstream = error is UpstreamError ? error : null;
  return {
    'at': at,
    'status': page?.status ?? upstream?.status,
    'error': upstream == null
        ? error.runtimeType.toString()
        : upstream.cause ?? (upstream.status == null ? 'UpstreamError' : 'HTTP'),
    'bytes': page?.bytes ?? upstream?.bytes ?? 0,
    'parsed': 0,
    'reason': page == null ? 'not parsed' : 'parser threw',
  };
}

/// The last chefs fetch report, for the frame stats screen. Set by each scrape
/// and by the backend whenever it reads the snapshot, so a stored report shows
/// after a restart.
final ValueNotifier<Map<String, dynamic>?> chefsDiagnostics = ValueNotifier(
  null,
);

/// "at 2026-10-23 16:32" on the campus clock. The space lets a narrow line
/// wrap there rather than inside an ISO stamp.
String? _readAt(Object? raw) {
  final at = _stamp(raw);
  if (at == null) return null;
  final stamp = CampusTime.format(at);
  return 'at ${stamp.substring(0, 10)} ${stamp.substring(11, 16)}';
}

/// [chefsDiagnostics] as text, one line per page, for the screen and the
/// copied report.
List<String> chefsDiagnosticsLines(Map<String, dynamic>? report) {
  if (report == null) return const ['No chefs fetch yet'];
  String line(String page, Object? raw) {
    if (raw is! Map) return '$page: not read';
    final parts = <String>[
      if (raw['status'] != null) 'HTTP ${raw['status']}',
      if (raw['error'] != null) 'failed, ${raw['error']}',
      if (raw['bytes'] != null) '${raw['bytes']} bytes',
      if (raw['parsed'] != null) '${raw['parsed']} chefs',
      if (raw['skipped'] != null) '${raw['skipped']} skipped',
      if (raw['untimed'] != null) '${raw['untimed']} without a time',
      if (raw['reason'] != null) '${raw['reason']}',
      ?_readAt(raw['at']),
    ];
    return '$page: ${parts.join(', ')}';
  }

  return [
    line('Menus page', report['menus']),
    line('Schedule page', report['schedule']),
  ];
}

/// Whether this snapshot is not a clean read of both pages: the last attempt
/// failed, or it predates the `*_ok` fields. Such a snapshot is retried after
/// five minutes instead of thirty, and pull to refresh waits the same five.
bool ritChefsFailed(Map<String, dynamic> snapshot) =>
    snapshot['today_ok'] != true || snapshot['schedule_ok'] != true;

DateTime? _stamp(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// When this feed last held real chef information: a `/menus` read with chefs,
/// a schedule read that covered its day, or today's TigerCenter payload with a
/// visiting chef in it. A TigerCenter payload that merely has menus is not
/// that, so a first run outage reports null rather than the moment the failed
/// fetch happened.
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
        menuItemsWithCategory(tigerCenter!, visitingChef).isNotEmpty)
      tigerCenterAt.toUtc(),
  ]..sort();
  return stamps.isEmpty ? null : stamps.last;
}

// --- projection --------------------------------------------------------

/// Lower case, ampersand as "and", letters and digits only, no leading "the".
/// The visiting chefs page matches locations by name alone.
String normalizeLocationName(String name) {
  var value = name.toLowerCase().replaceAll('&', ' and ').replaceAll('é', 'e');
  value = value.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value.startsWith('the ') ? value.substring(4) : value;
}

/// Names RIT has used for the same location, TigerCenter's first. rit.edu
/// pages have used new names before TigerCenter did, and a chef there must
/// still find its location.
const List<List<String>> locationAliases = [
  ['Kitchen at Brick City', 'Brick City Cafe', 'Brick City'],
  ['RITZ', 'RITZ Sports Zone', 'Ritz Sports Zone'],
  ['The Cafe & Market at Crossroads', 'Crossroads', 'Cafe at Crossroads',
    'Market at Crossroads', 'Crossroads Cafe'],
  ["Gracie's", 'Gracies'],
];

final Map<String, String> _aliasKeys = {
  for (final names in locationAliases)
    for (final name in names)
      normalizeLocationName(name): normalizeLocationName(names.first),
};

/// One key per location, whichever name it goes by. An unknown name is its
/// own key, so a chef there still shows under RIT's name.
String locationKey(String name) {
  final normal = normalizeLocationName(name);
  return _aliasKeys[normal] ?? normal;
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
    locationIds[locationKey(loc['name'] as String? ?? '')] = loc['id'] as int;
  }

  final menusPart = rit?['today'] as Map<String, dynamic>?;
  // Cached chefs keep showing whatever happened since. /menus can only ever
  // add chefs here; it never says "none today".
  final menusToday = menusPart != null &&
      menusPart['date'] == today &&
      menusPart['found'] == true;
  // Confirming a quiet day is opt in: snapshots stored before the ok/unknown
  // fields existed lack them, and one of those once marked an unparsed day as
  // empty. They still show their chefs, and `ritChefsFailed` has them refetched.
  final schedule = rit?['schedule'] as Map<String, dynamic>?;
  var scheduleToday = schedule?[today] as Map<String, dynamic>?;
  // A day block the parser could not read says nothing, either way.
  if (scheduleToday?['unknown'] == true) scheduleToday = null;
  // The one place a quiet day comes from rit.edu: the schedule page lists
  // today's block and positively marks it empty, on a read that succeeded
  // today. A read from an earlier service day listed today ahead of time, and
  // may since have changed, so it cannot confirm. `schedule_at` is that read's
  // time, stamped on the campus clock when the schedule page last parsed.
  final readAt = _stamp(rit?['schedule_at']);
  final readToday = readAt != null && CampusTime.formatDate(readAt) == today;
  final scheduleConfirms =
      readToday &&
      scheduleToday != null &&
      scheduleToday['empty'] == true &&
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
      'location_id':
          c['location_id'] ??
          locationIds[locationKey(c['location_name'] as String? ?? '')],
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
        'location_id': locationIds[locationKey(name)],
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
      '${locationId ?? locationKey('$locationName')}|'
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
    return {'items': items, 'availability': availabilityAvailable, 'next': _nextChef(schedule, today)};
  }

  // The only way to a quiet day. TigerCenter publishing menus without a chef
  // is not enough: that feed is the one that went quiet, and nothing in it
  // says whether a chef was meant to be there.
  if (scheduleConfirms) {
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
