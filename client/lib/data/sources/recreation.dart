/// Gym, fitness and pool hours from RIT Recreation and Wellness.
///
/// Ported from `backend/app/scrapers/recreation.py`.
///
/// Source: https://www.rit.edu/recreationwellness/facility-hours
///
/// This is an HTML scrape rather than an API, because RIT publishes no feed for
/// it. The markup is stable and well structured though: each facility is a named
/// collapse panel followed by a `table.seven-day-schedule` of day and hours
/// pairs, so this targets that structure rather than guessing at text positions.
///
/// The Python used plain regular expressions rather than an HTML library, so
/// this ports directly and needs no HTML parser dependency.
///
/// Hour strings are prose and can hold several sessions in one cell, for example
/// the Aquatics Center's "6:45am - 8:45am, 12pm - 1:45pm, 7pm - 10pm". Each
/// comma separated segment becomes its own span, which is what makes a pool
/// schedule usable rather than a single misleading open-to-close range.
library;

import '../campus_time.dart';
import '../upstream.dart';

const String recreationSource = 'recreation_hours';
const String recreationUrl =
    'https://www.rit.edu/recreationwellness/facility-hours';

const Map<String, int> _weekdayNames = {
  'monday': 0,
  'tuesday': 1,
  'wednesday': 2,
  'thursday': 3,
  'friday': 4,
  'saturday': 5,
  'sunday': 6,
};

final RegExp _nameRe =
    RegExp(r'<span class="overflow-hidden">\s*(.*?)\s*</span>', dotAll: true);
final RegExp _tableRe = RegExp(
  r'<table[^>]*class="[^"]*seven-day-schedule[^"]*"[^>]*>(.*?)</table>',
  dotAll: true,
);
final RegExp _rowRe =
    RegExp(r'<tr>\s*<th>(.*?)</th>\s*<td>(.*?)</td>\s*</tr>', dotAll: true);
final RegExp _tagsRe = RegExp(r'<[^>]+>');

const Map<String, String> _entities = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&rsquo;': '’',
  '&ndash;': '–',
  '&mdash;': '—',
};

/// Strip tags and entities down to a single clean line.
String textOf(String raw) {
  var value = raw.replaceAll(_tagsRe, ' ');
  _entities.forEach((entity, replacement) {
    value = value.replaceAll(entity, replacement);
  });
  value = value.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!)),
  );
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Turn '6:45am', '10am', '12pm', 'noon' into 'HH:MM'.
String? parseRecreationTime(String token) {
  final value = token.trim().toLowerCase().replaceAll('.', '');
  if (value == 'noon' || value == '12noon') return '12:00';
  if (value == 'midnight') return '00:00';

  final match =
      RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$').firstMatch(value);
  if (match == null) return null;

  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2) ?? '0');
  final meridiem = match.group(3);

  if (meridiem == 'pm' && hour != 12) {
    hour += 12;
  } else if (meridiem == 'am' && hour == 12) {
    hour = 0;
  }
  if (hour > 23 || minute > 59) return null;

  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

/// Split one cell into concrete spans. Closed yields an empty list.
List<Map<String, String>> parseHoursCell(String cell) {
  final value = textOf(cell);
  if (value.isEmpty || value.toLowerCase().contains('closed')) return const [];

  final spans = <Map<String, String>>[];
  for (final segment in value.split(',')) {
    // An en dash, em dash or hyphen separates the two ends.
    final parts = segment.trim().split(RegExp(r'\s*[-–—]\s*'));
    if (parts.length != 2) continue;
    final opens = parseRecreationTime(parts[0]);
    final closes = parseRecreationTime(parts[1]);
    if (opens != null && closes != null) {
      spans.add({'opens_at': opens, 'closes_at': closes});
    }
  }
  return spans;
}

final RegExp _dayRe = RegExp(
  r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
  caseSensitive: false,
);

/// 'Saturday (Today)' becomes 5.
///
/// Scans for a weekday anywhere in the label rather than taking the first word,
/// because the header row runs into the first data row in this markup and
/// yields 'Date Hours Saturday (Today)'. Taking the first word dropped today's
/// row entirely.
int? weekdayOf(String label) {
  final match = _dayRe.firstMatch(textOf(label));
  return match == null ? null : _weekdayNames[match.group(1)!.toLowerCase()];
}

/// The page shows the next seven days starting today.
DateTime resolveServiceDate(int weekday, DateTime today) {
  // DateTime.weekday is 1..7 from Monday; the table's index is 0..6.
  final todayIndex = today.weekday - 1;
  return today.add(Duration(days: (weekday - todayIndex) % 7));
}

List<Map<String, dynamic>> parseRecreation(String html, {DateTime? today}) {
  final reference = today ?? CampusTime.dateOf(CampusTime.nowUtc());

  // Walk names and tables together in document order, pairing each table with
  // the closest preceding name.
  final names = [
    for (final m in _nameRe.allMatches(html)) (m.start, textOf(m.group(1)!)),
  ];

  final rows = <Map<String, dynamic>>[];

  for (final table in _tableRe.allMatches(html)) {
    String? facility;
    for (final (position, name) in names) {
      if (position < table.start && name.isNotEmpty) facility = name;
    }
    if (facility == null) continue;

    for (final row in _rowRe.allMatches(table.group(1)!)) {
      final weekday = weekdayOf(row.group(1)!);
      if (weekday == null) continue;

      final serviceDate = resolveServiceDate(weekday, reference);
      final key = '${serviceDate.year}-'
          '${serviceDate.month.toString().padLeft(2, '0')}-'
          '${serviceDate.day.toString().padLeft(2, '0')}';

      final spans = parseHoursCell(row.group(2)!);

      if (spans.isEmpty) {
        final note = textOf(row.group(2)!);
        rows.add({
          'facility': facility,
          'service_date': key,
          'opens_at': null,
          'closes_at': null,
          'closed': true,
          'note': note.isEmpty ? 'Closed' : note,
        });
        continue;
      }

      for (final span in spans) {
        rows.add({
          'facility': facility,
          'service_date': key,
          'opens_at': span['opens_at'],
          'closes_at': span['closes_at'],
          'closed': false,
          'note': null,
        });
      }
    }
  }

  return rows;
}

Future<Map<String, dynamic>> scrapeRecreation(Upstream http) async {
  final rows = parseRecreation(await http.getText(recreationUrl));
  if (rows.isEmpty) {
    throw UpstreamError('recreation hours page produced zero rows');
  }
  return {'rows': rows};
}

// --- projections -------------------------------------------------------

/// Group the flat scraped rows into what the UI reads: one entry per facility,
/// each holding one entry per date, each holding its spans.
///
/// The scrape produces one row per span, because a pool day has several
/// sessions. The card wants them nested, and a facility with a single
/// open-to-close range would be a lie about the middle of the day.
List<Map<String, dynamic>> recreationFacilities(Map<String, dynamic>? snapshot) {
  final byFacility = <String, Map<String, Map<String, dynamic>>>{};
  final order = <String>[];

  for (final raw in snapshot?['rows'] as List<dynamic>? ?? const []) {
    final row = raw as Map<String, dynamic>;
    final facility = '${row['facility']}';
    final date = '${row['service_date']}';

    final days = byFacility.putIfAbsent(facility, () {
      order.add(facility);
      return <String, Map<String, dynamic>>{};
    });

    final day = days.putIfAbsent(
      date,
      () => {
        'service_date': date,
        'closed': row['closed'] == true,
        'note': row['note'],
        'spans': <Map<String, dynamic>>[],
      },
    );

    if (row['closed'] == true) {
      day['closed'] = true;
      day['note'] = row['note'];
      continue;
    }

    day['closed'] = false;
    (day['spans'] as List<Map<String, dynamic>>).add({
      'opens_at': row['opens_at'],
      'closes_at': row['closes_at'],
    });
  }

  return [
    for (final facility in order)
      {
        'name': facility,
        'days': [
          for (final date in (byFacility[facility]!.keys.toList()..sort()))
            byFacility[facility]![date]!,
        ],
      },
  ];
}
