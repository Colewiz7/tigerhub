/// The colour of a dining location's name on a visiting chef row.
///
/// One fixed colour per location id, so a place reads the same on the Today
/// card, the Dining tab and the all chefs sheet. The name is always written
/// out beside it, so the colour only helps and is never the one cue. Each
/// colour is text on a card surface and holds 4.5:1 against every surface
/// step in both themes (see `chef_location_color_test.dart`).
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import 'sources/rit_chefs.dart' show locationKey;

class ChefLocationColor {
  const ChefLocationColor(this.name, this.light, this.dark);

  /// The TigerCenter name, for a chef whose feed gave a name and no id.
  final String name;
  final Color light;
  final Color dark;
}

/// Locations that host visiting chefs, by TigerCenter id. Anything else falls
/// back to the scheme's muted text colour, which is what the line used before.
const Map<int, ChefLocationColor> chefLocationColors = {
  21: ChefLocationColor("Gracie's", Color(0xFF7B3F9E), Color(0xFFDDB3F5)),
  22: ChefLocationColor('Kitchen at Brick City', Color(0xFF2E6B30), Color(0xFF9BD89A)),
  23: ChefLocationColor('The Cafe & Market at Crossroads', Color(0xFF2B4FB5), Color(0xFF9DC4FF)),
  24: ChefLocationColor('The Commons', Color(0xFF7A5200), Color(0xFFEBC15F)),
  26: ChefLocationColor('RITZ', Color(0xFFA8244F), Color(0xFFFF9FB0)),
  28: ChefLocationColor("Sol's Underground", Color(0xFF006874), Color(0xFF62D6E0)),
};

final Map<String, int> _idByName = {
  for (final e in chefLocationColors.entries) locationKey(e.value.name): e.key,
};

/// The id to colour by: the feed's own, else the one the name resolves to.
int? chefLocationId(MenuItem chef) =>
    chef.locationId ?? _idByName[locationKey(chef.locationName)];

Color chefLocationColor(MenuItem chef, ColorScheme scheme) {
  final entry = chefLocationColors[chefLocationId(chef)];
  if (entry == null) return scheme.onSurfaceVariant;
  return scheme.brightness == Brightness.dark ? entry.dark : entry.light;
}
