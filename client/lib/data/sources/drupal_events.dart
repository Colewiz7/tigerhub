/// Official RIT events from the public Drupal JSON:API.
///
/// Ported from `backend/app/scrapers/drupal_events.py`.
///
/// Endpoint: https://www.rit.edu/jsonapi/node/event
/// Verified 2026-08-28. This replaced the planned HTML scrape entirely: the
/// JSON:API module is publicly exposed and returns about 450 structured events.
///
/// Paginates at 50, so page[limit] is set explicitly and links.next is
/// followed. Sparse fieldsets keep the payload small; no image data is asked
/// for, which matters more now that the fetch happens on a phone.
library;

import '../campus_time.dart';
import '../upstream.dart';

const String drupalSource = 'drupal';
const String drupalBaseUrl = 'https://www.rit.edu/jsonapi/node/event';

const List<String> drupalFields = [
  'title',
  'body',
  'field_start_date',
  'field_start_time',
  'field_end_date',
  'field_end_time',
  'field_building',
  'field_room_location',
  'field_event_type',
  'field_link',
  'path',
  'changed',
];

const int drupalPageLimit = 50;

/// Backstop so a pagination bug cannot loop forever.
const int drupalMaxPages = 20;

/// `3:00 PM`, `15:00`, `15:00:00`. Returns null if it is none of those.
///
/// The 12 hour form is the one Drupal actually sends, and missing it is what
/// made every official RIT event look like an all day event.
(int, int, int)? parseClockOf(String raw) {
  final value = raw.trim().toUpperCase();
  if (value.isEmpty) return null;

  var isPm = false;
  var isAm = false;
  var body = value;
  if (body.endsWith('AM') || body.endsWith('PM')) {
    isPm = body.endsWith('PM');
    isAm = !isPm;
    body = body.substring(0, body.length - 2).trim();
  }

  final parts = body.split(':');
  final hour = parts.isEmpty ? null : int.tryParse(parts[0].trim());
  if (hour == null) return null;
  final minute = parts.length > 1 ? int.tryParse(parts[1].trim()) : 0;
  if (minute == null) return null;
  final second = parts.length > 2 ? int.tryParse(parts[2].trim()) ?? 0 : 0;

  var resolved = hour;
  if (isPm && hour < 12) resolved = hour + 12;
  if (isAm && hour == 12) resolved = 0;
  if (resolved > 23 || minute > 59 || second > 59) return null;

  return (resolved, minute, second);
}

/// Drupal splits date and time. Recombine into one campus local timestamp.
///
/// **Drupal publishes the time in 12 hour form**, as `"3:00 PM"`. The backend
/// only ever tried `%H:%M:%S` and `%H:%M`, so every parse failed and fell
/// through to the all day branch: 456 of 460 official RIT events carried a
/// stated start time that was thrown away and rendered as midnight, all day.
/// That is why the Events tab showed everything from RIT as ALL DAY.
///
/// Only a date with genuinely no time is an all day event, which is the
/// remaining 4.
///
/// A stated `12:00 AM` is treated as a real midnight, not as an all day marker.
/// Twelve records pair it with an `11:59 PM` end, which probably is a CMS
/// spelling of "all day", but guessing that would also hide a genuine midnight
/// event, and this file does not infer what the source did not say.
(String?, bool) combineDrupalMoment(Object? day, Object? clock) {
  if (day is! String || day.isEmpty) return (null, false);

  final date = DateTime.tryParse(day);
  if (date == null) return (null, false);

  String at(int h, int m, int s) => CampusTime.format(
        CampusTime.wall(date.year, date.month, date.day, h, m, s),
      );

  if (clock is! String || clock.trim().isEmpty) return (at(0, 0, 0), true);

  final parsed = parseClockOf(clock);
  if (parsed == null) return (at(0, 0, 0), true);

  final (hour, minute, second) = parsed;
  return (at(hour, minute, second), false);
}

List<Map<String, dynamic>> parseDrupal(List<dynamic> records) {
  final out = <Map<String, dynamic>>[];

  for (final record in records) {
    if (record is! Map<String, dynamic>) continue;
    final attrs = record['attributes'] as Map<String, dynamic>? ?? const {};

    final (startsAt, allDay) = combineDrupalMoment(
      attrs['field_start_date'],
      attrs['field_start_time'],
    );
    if (startsAt == null) continue;

    final (endsAt, _) = combineDrupalMoment(
      attrs['field_end_date'],
      attrs['field_end_time'],
    );

    final uid = record['id'] as String? ?? '';
    if (uid.isEmpty) continue;

    final body = attrs['body'];
    final link = attrs['field_link'];
    final alias = (attrs['path'] as Map<String, dynamic>?)?['alias'] as String?;

    out.add({
      'uid': uid,
      'source': drupalSource,
      'title': (attrs['title'] as String? ?? '').trim(),
      'description': body is Map<String, dynamic> ? body['value'] : null,
      'location': attrs['field_room_location'],
      'building': attrs['field_building'],
      'room': attrs['field_room_location'],
      // Drupal events are university published, not club published.
      'organizer': 'RIT',
      'organizer_key': 'RIT',
      'event_type': attrs['field_event_type'],
      'url': (link is Map<String, dynamic> ? link['uri'] : null) ??
          (alias == null ? null : 'https://www.rit.edu$alias'),
      'starts_at': startsAt,
      'ends_at': endsAt,
      'all_day': allDay,
    });
  }

  return out;
}

/// Follow links.next until exhausted, returning raw JSON:API records.
Future<List<dynamic>> fetchDrupal(Upstream http) async {
  final fields = drupalFields.join(',');
  String? url = '$drupalBaseUrl?page%5Blimit%5D=$drupalPageLimit'
      '&fields%5Bnode--event%5D=${Uri.encodeQueryComponent(fields)}';

  final records = <dynamic>[];

  for (var page = 0; page < drupalMaxPages && url != null; page++) {
    final payload = await http.getJson(url) as Map<String, dynamic>;
    records.addAll(payload['data'] as List<dynamic>? ?? const []);
    final next = (payload['links'] as Map<String, dynamic>?)?['next'];
    // links.next already carries the full query string.
    url = next is Map<String, dynamic> ? next['href'] as String? : null;
  }

  return records;
}

Future<Map<String, dynamic>> scrapeDrupal(Upstream http) async {
  final parsed = parseDrupal(await fetchDrupal(http));
  if (parsed.isEmpty) {
    throw UpstreamError('Drupal JSON:API produced zero events');
  }
  return {'events': parsed};
}
