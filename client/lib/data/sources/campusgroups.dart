/// CampusGroups student club events, from the public all events iCal feed.
///
/// Ported from `backend/app/scrapers/campusgroups.py`.
///
/// Feed: https://campusgroups.rit.edu/ical/rit/ical_rit.ics (302s to a CDN).
/// Verified 2026-08-28: 921 events, every field present on 100% of them, and
/// zero RRULEs because recurrences arrive pre expanded.
///
/// The X-CG-CATEGORY=club_acronym parameter is kept as organizer_key. It joins
/// cleanly to the Drupal node--student_club slug (60 of 60 in the feed), which
/// is what lets the app show real club names and mute a noisy organizer.
library;

import '../ical.dart';
import '../upstream.dart';

const String campusGroupsFeed =
    'https://campusgroups.rit.edu/ical/rit/ical_rit.ics';

const String campusGroupsSource = 'campusgroups';

/// CampusGroups puts prompts in the LOCATION field when an event hides its
/// venue. These are UI text, not addresses, and must never reach the client.
const List<String> _placeholderLocations = [
  'sign in to download',
  'sign in to view',
  'log in to view',
  'see description',
  'tba',
  'to be announced',
  'n/a',
];

/// Reduce a LOCATION line to just the venue name.
///
/// The feed sends a full postal address, usually repeating the venue:
///
///   "RIT FoodShare (113 Riverknoll), 113 Riverknoll, Rochester, NY 14623, United States"
///
/// Nobody needs the ZIP code of a campus building, so only the first segment is
/// kept. Placeholder prompts return null so no subtitle is rendered at all.
String? cleanLocation(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  final lowered = value.toLowerCase();
  for (final marker in _placeholderLocations) {
    if (lowered.contains(marker)) return null;
  }

  final venue = value.split(',').first.trim();
  return venue.isEmpty ? null : venue;
}

/// Pull the club acronym and the event type out of the CATEGORIES lines.
(String?, String?) categoriesOf(IcalEvent event) {
  String? acronym;
  String? eventType;
  for (final property in event.all('CATEGORIES')) {
    switch (property.params['X-CG-CATEGORY']) {
      case 'club_acronym':
        acronym = property.value;
      case 'event_type':
        eventType = property.value;
    }
  }
  return (acronym, eventType);
}

List<Map<String, dynamic>> parseCampusGroups(String raw) {
  final out = <Map<String, dynamic>>[];

  for (final event in parseEvents(raw)) {
    final uid = event.text('UID');
    if (uid == null) continue;

    final start = parseMoment(event.first('DTSTART'));
    if (start == null) continue;
    final end = parseMoment(event.first('DTEND'));

    final (acronym, eventType) = categoriesOf(event);

    out.add({
      'uid': uid,
      'source': campusGroupsSource,
      'title': event.text('SUMMARY') ?? '',
      'description': event.text('DESCRIPTION'),
      'location': cleanLocation(event.text('LOCATION')),
      'building': null,
      'room': null,
      'organizer': event.first('ORGANIZER')?.params['CN'],
      'organizer_key': acronym?.toUpperCase(),
      'event_type': eventType,
      'url': event.text('URL'),
      'starts_at': formatUtc(start.instant),
      'ends_at': end == null ? null : formatUtc(end.instant),
      'all_day': start.allDay,
    });
  }

  return out;
}

Future<Map<String, dynamic>> scrapeCampusGroups(Upstream http) async {
  final parsed = parseCampusGroups(await http.getText(campusGroupsFeed));
  if (parsed.isEmpty) {
    throw UpstreamError('iCal feed produced zero events');
  }
  return {'events': parsed};
}
