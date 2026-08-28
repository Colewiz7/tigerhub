/// Event filtering.
///
/// Two independent filters, because the two do not split cleanly by organizer.
/// The same organizer posts both a club fair and a free ice cream giveaway.
///
///   1. Organizer muting, mechanical, kills most of the noise
///   2. Keyword rules on the title, for what survives
///
/// Nothing is ever silently dropped. Every result carries the events it hid
/// and why, so the UI can show a count and reveal them on demand.
library;

import '../models/api_models.dart';
import 'preferences.dart';

enum HiddenReason { mutedOrganizer, hiddenKeyword }

class FilteredEvent {
  const FilteredEvent({
    required this.event,
    this.boosted = false,
    this.hiddenReason,
  });

  final CampusEvent event;

  /// Matched a boost keyword. Sorts to the top of its group.
  final bool boosted;

  /// Null when the event is visible.
  final HiddenReason? hiddenReason;

  bool get isHidden => hiddenReason != null;
}

class FilteredGroup {
  const FilteredGroup({
    required this.organizer,
    required this.organizerKey,
    required this.visible,
    required this.hidden,
  });

  final String organizer;
  final String? organizerKey;
  final List<FilteredEvent> visible;
  final List<FilteredEvent> hidden;

  int get hiddenCount => hidden.length;
  int get total => visible.length + hidden.length;
}

class FilterResult {
  const FilterResult({required this.groups, required this.hiddenTotal});

  /// Groups with at least one visible event. A fully muted organizer never
  /// leaves an empty header behind.
  final List<FilteredGroup> groups;

  /// Everything hidden, across every group including fully hidden ones.
  final int hiddenTotal;
}

bool _matches(String title, List<String> keywords) {
  final lowered = title.toLowerCase();
  return keywords.any((k) => k.isNotEmpty && lowered.contains(k));
}

/// Apply both filters and group by organizer.
FilterResult filterEvents(List<CampusEvent> events, Preferences prefs) {
  final byOrganizer = <String, List<CampusEvent>>{};
  final keys = <String, String?>{};
  for (final event in events) {
    final name = event.organizer ?? 'Other';
    byOrganizer.putIfAbsent(name, () => []).add(event);
    keys[name] = event.organizerKey;
  }

  final groups = <FilteredGroup>[];
  var hiddenTotal = 0;

  for (final entry in byOrganizer.entries) {
    final key = keys[entry.key];
    final muted = key != null && prefs.mutedOrganizers.contains(key);

    final visible = <FilteredEvent>[];
    final hidden = <FilteredEvent>[];

    for (final event in entry.value) {
      if (muted) {
        hidden.add(FilteredEvent(
          event: event,
          hiddenReason: HiddenReason.mutedOrganizer,
        ));
        continue;
      }
      if (prefs.keywordRulesEnabled &&
          _matches(event.title, prefs.hideKeywords)) {
        hidden.add(FilteredEvent(
          event: event,
          hiddenReason: HiddenReason.hiddenKeyword,
        ));
        continue;
      }
      visible.add(FilteredEvent(
        event: event,
        boosted: prefs.keywordRulesEnabled &&
            _matches(event.title, prefs.boostKeywords),
      ));
    }

    // Boosted first, then by start time.
    visible.sort((a, b) {
      if (a.boosted != b.boosted) return a.boosted ? -1 : 1;
      return a.event.startsAt.compareTo(b.event.startsAt);
    });
    hidden.sort((a, b) => a.event.startsAt.compareTo(b.event.startsAt));

    hiddenTotal += hidden.length;

    // A group with nothing visible is dropped entirely, so muting an organizer
    // does not leave a header with no rows under it. Its events still count
    // toward hiddenTotal, so they stay recoverable.
    if (visible.isNotEmpty) {
      groups.add(FilteredGroup(
        organizer: entry.key,
        organizerKey: key,
        visible: visible,
        hidden: hidden,
      ));
    }
  }

  groups.sort((a, b) => b.visible.length.compareTo(a.visible.length));
  return FilterResult(groups: groups, hiddenTotal: hiddenTotal);
}

/// Organizer facets for the settings list, with counts.
class OrganizerFacet {
  const OrganizerFacet({
    required this.name,
    required this.key,
    required this.count,
  });

  final String name;
  final String? key;
  final int count;
}

List<OrganizerFacet> organizerFacets(List<CampusEvent> events) {
  final counts = <String, int>{};
  final keys = <String, String?>{};
  for (final event in events) {
    final name = event.organizer ?? 'Other';
    counts[name] = (counts[name] ?? 0) + 1;
    keys[name] = event.organizerKey;
  }
  final facets = [
    for (final entry in counts.entries)
      OrganizerFacet(name: entry.key, key: keys[entry.key], count: entry.value),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return facets;
}
