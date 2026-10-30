/// Which dining places are hidden, by hand or because their group is.
library;

import 'dining_layout.dart';

/// A place named in the group table, for matching a chef by name.
typedef GroupPlace = ({int id, String name});

// A hidden group covers its hide ids when it has a list, else every place
// that resolves into it. Other can never be hidden.
Set<String> groupHiddenIds({
  required Set<String> hiddenGroups,
  required DiningLayout layout,
  required List<GroupDef> defaults,
  required String Function(int placeId) defaultGroupOf,
  required Map<String, Set<int>> hideIds,
  required Iterable<int> placeIds,
}) {
  if (hiddenGroups.isEmpty) return const {};
  final resolved = layout.resolve(
    defaults: defaults,
    defaultGroupOf: defaultGroupOf,
    placeIds: placeIds.toList(),
  );
  return {
    for (final group in resolved)
      if (group.id != otherGroupId && hiddenGroups.contains(group.id))
        for (final id in group.placeIds)
          if (hideIds[group.id] == null || hideIds[group.id]!.contains(id)) '$id',
  };
}

// hidden by hand plus hidden through a group
Set<String> effectiveHiddenIds({
  required Set<String> hidden,
  required Set<String> hiddenGroups,
  required DiningLayout layout,
  required List<GroupDef> defaults,
  required String Function(int placeId) defaultGroupOf,
  required Map<String, Set<int>> hideIds,
  required Iterable<int> placeIds,
}) => {
  ...hidden,
  ...groupHiddenIds(
    hiddenGroups: hiddenGroups,
    layout: layout,
    defaults: defaults,
    defaultGroupOf: defaultGroupOf,
    hideIds: hideIds,
    placeIds: placeIds,
  ),
};
