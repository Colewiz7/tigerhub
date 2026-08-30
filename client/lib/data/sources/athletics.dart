/// RIT athletics fixtures.
///
/// Ported from `backend/app/scrapers/athletics.py`.
///
/// Source: https://ritathletics.com/calendar.ashx/calendar.ics
///
/// This was written off once and should not have been. The Drupal
/// `node--athletics_event` resource exists but is empty, and the obvious
/// Sidearm JSON endpoints all 404, so the first pass concluded there was no
/// feed. There is: the same site publishes a plain iCal calendar. 182 fixtures,
/// September through March.
///
/// Fixtures are events, so they go in the same merged list with
/// `source = athletics` rather than getting a parallel one. Organizer is set to
/// the sport, pulled off the summary, so grouping and muting work on them with
/// no special cases.
///
/// Unlike CampusGroups, the full LOCATION is kept: "Rochester, N.Y. / Judson
/// Stadium" is the whole useful answer for a fixture, and trimming at the first
/// comma would leave just "Rochester".
library;

import '../campus_time.dart';
import '../ical.dart';
import '../upstream.dart';

const String athleticsFeed = 'https://ritathletics.com/calendar.ashx/calendar.ics';

const String athleticsSource = 'athletics';

/// "Women's Soccer vs Geneseo - Pride Game" -> "Women's Soccer"
final RegExp _sportRe = RegExp(r"^(.*?)\s+(?:vs\.?|at)\s+", caseSensitive: false);

/// The sport, so fixtures group and mute like any other organizer.
String? sportOf(String summary) {
  final match = _sportRe.firstMatch(summary.trim());
  final captured = match?.group(1)?.trim();
  if (captured != null && captured.isNotEmpty) return captured;

  // Meets and invitationals do not use vs/at. Fall back to the leading words.
  final words = summary.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return words.length >= 2 ? words.take(2).join(' ') : null;
}

List<Map<String, dynamic>> parseAthletics(String raw) {
  final out = <Map<String, dynamic>>[];

  for (final event in parseEvents(raw)) {
    final uid = event.text('UID');
    final summary = event.text('SUMMARY');
    if (uid == null || summary == null) continue;

    final start = parseMoment(event.first('DTSTART'));
    if (start == null) continue;
    final end = parseMoment(event.first('DTEND'));

    final sport = sportOf(summary);

    out.add({
      'uid': uid,
      'source': athleticsSource,
      'title': summary,
      'description': event.text('DESCRIPTION'),
      'location': event.text('LOCATION'),
      'building': null,
      'room': null,
      'organizer': sport ?? 'RIT Athletics',
      'organizer_key': (sport ?? 'ATHLETICS').toUpperCase().replaceAll(' ', '_'),
      'event_type': 'Athletics',
      'url': event.text('URL'),
      // Athletics times are rendered in campus time, not UTC, which is what
      // the backend stored and what the fixtures read as locally.
      'starts_at': CampusTime.format(start.instant),
      'ends_at': end == null ? null : CampusTime.format(end.instant),
      'all_day': start.allDay,
    });
  }

  return out;
}

Future<Map<String, dynamic>> scrapeAthletics(Upstream http) async {
  final parsed = parseAthletics(await http.getText(athleticsFeed));
  if (parsed.isEmpty) {
    throw UpstreamError('athletics feed produced zero fixtures');
  }
  return {'events': parsed};
}
