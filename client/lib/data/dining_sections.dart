/// The Dining tab's sections: Pinned, the groups, then Hidden.
library;

import '../cards/dining_card.dart';
import '../models/api_models.dart';
import 'dining_layout.dart';

class GroupSection {
  const GroupSection({required this.group, required this.places});

  final ResolvedGroup group;
  final List<DiningLocation> places;
}

class DiningSections {
  const DiningSections({required this.pinned, required this.groups, required this.hidden});

  final List<DiningLocation> pinned;
  final List<GroupSection> groups;
  final List<DiningLocation> hidden;

  int get visibleCount => pinned.length + groups.fold(0, (sum, g) => sum + g.places.length);
}

// pinned is in pin order, a pinned place shows only in Pinned
DiningSections buildDiningSections({
  required List<DiningLocation> locations,
  required DiningLayout layout,
  required List<GroupDef> defaults,
  required String Function(int placeId) defaultGroupOf,
  required List<String> pinned,
  required Set<String> hidden,
  bool showHidden = true,
  // edit mode lists groups with no places too, apart from Other
  bool keepEmpty = false,
}) {
  bool isHidden(DiningLocation l) => hidden.contains('${l.id}');
  final visible = [
    for (final l in locations)
      if (!isHidden(l)) l,
  ];
  final pinnedPlaces = [
    for (final l in visible)
      if (pinned.contains('${l.id}')) l,
  ]..sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      return pinned.indexOf('${a.id}').compareTo(pinned.indexOf('${b.id}'));
    });
  final rest = [
    for (final l in visible)
      if (!pinned.contains('${l.id}')) l,
  ]..sort(compareForDisplay);
  final byId = {for (final l in rest) l.id: l};

  final groups = <GroupSection>[];
  final resolved = layout.resolve(defaults: defaults, defaultGroupOf: defaultGroupOf, placeIds: [for (final l in rest) l.id]);
  for (final group in resolved) {
    final ordered = [for (final id in group.placeIds) byId[id]!];
    // open first, a saved order holds within each half
    final places = [
      ...ordered.where((l) => l.isOpen),
      ...ordered.where((l) => !l.isOpen),
    ];
    if (places.isNotEmpty || (keepEmpty && group.id != otherGroupId)) groups.add(GroupSection(group: group, places: places));
  }

  final hiddenPlaces = showHidden
      ? ([
          for (final l in locations)
            if (isHidden(l)) l,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
      : <DiningLocation>[];
  return DiningSections(pinned: pinnedPlaces, groups: groups, hidden: hiddenPlaces);
}
