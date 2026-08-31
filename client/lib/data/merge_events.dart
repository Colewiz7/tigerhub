/// Merge the same event arriving from more than one feed.
///
/// docs/notes.md section 8 decision 2 shipped **no dedupe on purpose**, so the real
/// overlap could be observed before anyone wrote fuzzy matching. It has now
/// been observed, on device, 2026-08-30: **138 collisions across 1604 events**,
/// and they are exact matches on a normalised title plus the exact start
/// instant. No fuzzy matching is needed, which is a much smaller job than that
/// decision anticipated.
///
/// It only became measurable after the Drupal time fix. While every Drupal
/// event was pinned to midnight it could never share an instant with the
/// CampusGroups copy of itself, so the overlap read as zero.
///
/// ## The copies are not equivalent
///
/// This merges fields rather than picking a winner and discarding the rest,
/// because each feed is better at something:
///
///   athletics      names the sport, and carries the fullest location
///   campusgroups   names the real club, which grouping and muting run on
///   drupal         says "RIT" for everything, but splits building and room
///
/// Dropping the CampusGroups copy would silently break muting for that event,
/// since the surviving record would claim to be organised by "RIT".
library;

import 'sources/athletics.dart';
import 'sources/campusgroups.dart';
import 'sources/drupal_events.dart';

/// Lower is preferred as the base record.
const Map<String, int> sourceRank = {
  athleticsSource: 0,
  campusGroupsSource: 1,
  drupalSource: 2,
};

int _rankOf(Object? source) => sourceRank['$source'] ?? 99;

/// Lowercase, and collapse every run of non-alphanumerics to one space.
///
/// Deliberately not fuzzy. The measured collisions are exact once case and
/// punctuation are normalised, and anything looser starts merging genuinely
/// different events that happen to share a name and a time slot.
String normaliseTitle(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// The identity two records must share to be the same event.
String? eventKey(Map<String, dynamic> event) {
  final title = event['title'];
  if (title is! String || title.trim().isEmpty) return null;
  final startsAt = DateTime.tryParse(event['starts_at'] as String? ?? '');
  if (startsAt == null) return null;
  return '${normaliseTitle(title)}|${startsAt.toUtc().toIso8601String()}';
}

/// Fields worth taking from a lesser ranked copy when the preferred one has
/// nothing. Deliberately not `organizer` or `organizer_key`: those come from
/// the preferred source as a pair, and mixing a club's name with another
/// feed's key would break grouping.
const List<String> _fillable = [
  'description',
  'location',
  'building',
  'room',
  'url',
  'event_type',
  'ends_at',
];

bool _isEmpty(Object? value) =>
    value == null || (value is String && value.trim().isEmpty);

/// Collapse duplicates, keeping the best fields from every copy.
///
/// Input order does not matter; the result is deterministic. Records that
/// cannot produce a key (no title, or an unparseable start) are passed through
/// untouched rather than silently dropped.
List<Map<String, dynamic>> mergeDuplicateEvents(
  List<Map<String, dynamic>> events,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final passthrough = <Map<String, dynamic>>[];
  final order = <String>[];

  for (final event in events) {
    final key = eventKey(event);
    if (key == null) {
      passthrough.add(event);
      continue;
    }
    if (!groups.containsKey(key)) order.add(key);
    groups.putIfAbsent(key, () => []).add(event);
  }

  final merged = <Map<String, dynamic>>[];

  for (final key in order) {
    final copies = groups[key]!;
    if (copies.length == 1) {
      merged.add(copies.first);
      continue;
    }

    // Stable: rank first, then uid, so the same input always picks the same
    // base regardless of the order the feeds happened to be read in.
    final ranked = [...copies]..sort((a, b) {
        final byRank = _rankOf(a['source']).compareTo(_rankOf(b['source']));
        if (byRank != 0) return byRank;
        return '${a['uid']}'.compareTo('${b['uid']}');
      });

    final base = Map<String, dynamic>.from(ranked.first);

    for (final other in ranked.skip(1)) {
      for (final field in _fillable) {
        if (_isEmpty(base[field]) && !_isEmpty(other[field])) {
          base[field] = other[field];
        }
      }
    }

    // Which feeds carried this, so the overlap stays visible rather than being
    // quietly erased. `source` keeps naming the base, as it always did.
    base['merged_from'] = [
      for (final copy in ranked) copy['source'],
    ];

    merged.add(base);
  }

  return [...merged, ...passthrough];
}
