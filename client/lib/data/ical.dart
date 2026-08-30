/// A small iCalendar reader, enough for the two feeds RIT publishes.
///
/// The backend used Python's `icalendar`. This is hand written rather than a
/// new dependency because the job turned out to be genuinely small: CLAUDE.md
/// 7.3 records that the CampusGroups feed contains **zero RRULEs**, recurrences
/// arriving pre expanded, so there is no recurrence engine to write. What is
/// left is line unfolding, parameter parsing, and text unescaping.
///
/// It handles exactly what the two feeds send, verified against both:
///
///   CampusGroups  962 VEVENTs, every DTSTART/DTEND a bare UTC timestamp
///   Athletics     182 VEVENTs, 146 UTC timestamps and 36 `VALUE=DATE` all days
///
/// Anything beyond that (VTIMEZONE, RRULE, PERIOD values) is deliberately not
/// implemented, because parsing something neither feed sends would be untested
/// code pretending to be a general library.
library;

import 'campus_time.dart';

class IcalProperty {
  const IcalProperty({
    required this.name,
    required this.params,
    required this.value,
  });

  final String name;
  final Map<String, String> params;
  final String value;
}

class IcalEvent {
  IcalEvent(this.properties);

  final List<IcalProperty> properties;

  IcalProperty? first(String name) {
    for (final p in properties) {
      if (p.name == name) return p;
    }
    return null;
  }

  List<IcalProperty> all(String name) =>
      [for (final p in properties) if (p.name == name) p];

  String? text(String name) {
    final value = first(name)?.value.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// Undo RFC 5545 line folding: a CRLF followed by one space or tab is a
/// continuation of the previous line, not a new one.
List<String> unfold(String raw) {
  final lines = <String>[];
  for (final line in raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    if (line.isEmpty) continue;
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.add(line);
    }
  }
  return lines;
}

/// Unescape a TEXT value. Athletics sends `Rochester\, N.Y.`, so this has to
/// run before anything splits a location on its commas.
String unescapeText(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    if (ch != r'\' || i + 1 >= value.length) {
      out.write(ch);
      continue;
    }
    final next = value[i + 1];
    i++;
    switch (next) {
      case 'n':
      case 'N':
        out.write('\n');
      case ',':
        out.write(',');
      case ';':
        out.write(';');
      case r'\':
        out.write(r'\');
      default:
        out.write(next);
    }
  }
  return out.toString();
}

/// Split `NAME;P=1;Q="a:b":VALUE` at the colon that ends the name and params.
/// A colon inside a quoted parameter value does not count.
IcalProperty? parseLine(String line) {
  var inQuotes = false;
  var split = -1;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ':' && !inQuotes) {
      split = i;
      break;
    }
  }
  if (split < 0) return null;

  final head = line.substring(0, split);
  final value = line.substring(split + 1);

  final parts = <String>[];
  var buffer = StringBuffer();
  inQuotes = false;
  for (var i = 0; i < head.length; i++) {
    final ch = head[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
      buffer.write(ch);
    } else if (ch == ';' && !inQuotes) {
      parts.add(buffer.toString());
      buffer = StringBuffer();
    } else {
      buffer.write(ch);
    }
  }
  parts.add(buffer.toString());

  final params = <String, String>{};
  for (final part in parts.skip(1)) {
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    var v = part.substring(eq + 1);
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    params[part.substring(0, eq).toUpperCase()] = v;
  }

  return IcalProperty(
    name: parts.first.toUpperCase(),
    params: params,
    value: unescapeText(value),
  );
}

List<IcalEvent> parseEvents(String raw) {
  final events = <IcalEvent>[];
  List<IcalProperty>? current;

  for (final line in unfold(raw)) {
    if (line == 'BEGIN:VEVENT') {
      current = [];
      continue;
    }
    if (line == 'END:VEVENT') {
      if (current != null) events.add(IcalEvent(current));
      current = null;
      continue;
    }
    if (current == null) continue;
    final property = parseLine(line);
    if (property != null) current.add(property);
  }

  return events;
}

/// A DTSTART or DTEND, resolved.
class IcalMoment {
  const IcalMoment(this.instant, this.allDay, this.wasUtc);

  /// The UTC instant the property names.
  final DateTime instant;

  /// True for a `VALUE=DATE` property, which names a day rather than a time.
  final bool allDay;

  /// True when the value carried a `Z`. Kept because the two feeds are
  /// serialised differently downstream and that difference is preserved.
  final bool wasUtc;
}

/// Parse `20260901T200000Z`, `20260901T200000`, or `20260901`.
IcalMoment? parseMoment(IcalProperty? property) {
  if (property == null) return null;
  final value = property.value.trim();
  if (value.length < 8) return null;

  int part(int start, int length) =>
      int.parse(value.substring(start, start + length));

  final year = part(0, 4);
  final month = part(4, 2);
  final day = part(6, 2);

  final isDate =
      property.params['VALUE'] == 'DATE' || !value.contains('T');
  if (isDate) {
    // A day, with no time. Midnight campus time is the moment it names.
    return IcalMoment(CampusTime.wall(year, month, day), true, false);
  }

  if (value.length < 15) return null;
  final hour = part(9, 2);
  final minute = part(11, 2);
  final second = part(13, 2);

  if (value.endsWith('Z')) {
    return IcalMoment(
      DateTime.utc(year, month, day, hour, minute, second),
      false,
      true,
    );
  }

  // Floating, or carrying a TZID. Neither feed sends a TZID, and a floating
  // value means local time where the event happens, which is campus.
  return IcalMoment(
    CampusTime.wall(year, month, day, hour, minute, second),
    false,
    false,
  );
}

/// ISO 8601 with a `Z` suffix, which is how the UTC valued feed was stored.
String formatUtc(DateTime instant) {
  final u = instant.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}
