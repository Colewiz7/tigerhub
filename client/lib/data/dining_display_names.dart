/// Short names for long dining places, for display only.
///
/// Ids, aliases, search and chef colours all keep the full name. Only text
/// drawn for a person goes through here, and every such surface calls these
/// functions. Last verified 2026-10-30. Small enough to live in code, and
/// each row is one line if this moves to JSON config later.
library;

import '../models/api_models.dart';
import 'chef_location_color.dart' show chefLocationId;
import 'sources/rit_chefs.dart' show locationKey, normalizeLocationName;

class DisplayName {
  const DisplayName(this.short, this.full, [this.variants = const []]);

  final String short;
  final String full;

  /// Other spellings that are not in the chef location aliases.
  final List<String> variants;
}

const Map<int, DisplayName> diningDisplayNames = {
  23: DisplayName('Crossroads', 'The Cafe & Market at Crossroads', ['Cafe & Market at Crossroads']),
  29: DisplayName('Market', 'The Market at Global Village', ['Market at Global Village']),
};

/// The name to draw for a place. Unknown places keep the name they came with.
String diningDisplayName(int? id, String name) => _entryFor(id, name)?.short ?? name;

/// The full name when [diningDisplayName] shortened it, else null.
String? diningFullName(int? id, String name) => _entryFor(id, name)?.full;

String locationDisplayName(DiningLocation location) =>
    diningDisplayName(location.id, location.name);

/// A chef's place, found by the feed's id or else by any name RIT has used.
String chefPlaceName(MenuItem chef) =>
    diningDisplayName(chefLocationId(chef), chef.locationName);

DisplayName? _entryFor(int? id, String name) {
  final byId = diningDisplayNames[id];
  if (byId != null) return byId;
  if (name.isEmpty) return null;
  final key = locationKey(name);
  final normal = normalizeLocationName(name);
  for (final entry in diningDisplayNames.values) {
    if (locationKey(entry.full) == key) return entry;
    if (entry.variants.any((v) => normalizeLocationName(v) == normal)) return entry;
  }
  return null;
}
