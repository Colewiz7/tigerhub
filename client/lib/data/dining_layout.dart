/// Dining tab layout stored as diffs from the shipped groups.
library;

import 'dart:convert';

const diningLayoutVersion = 1;
const otherGroupId = 'other';

typedef GroupDef = ({String id, String name});

class ResolvedGroup {
  const ResolvedGroup({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.placeIds,
  });

  final String id;
  final String name;
  final bool isDefault;
  final List<int> placeIds;
}

class DiningLayout {
  const DiningLayout({
    this.order = const [],
    this.custom = const {},
    this.moved = const {},
    this.renamed = const {},
    this.placeOrder = const {},
  });

  static const empty = DiningLayout();

  // group ids, only when the order differs from the default
  final List<String> order;
  // custom group id to name, in creation order
  final Map<String, String> custom;
  // place id to group id, only where it differs from the table
  final Map<int, String> moved;
  final Map<String, String> renamed;
  // group id to place ids, listed ones sort first
  final Map<String, List<int>> placeOrder;

  bool get isEmpty =>
      order.isEmpty &&
      custom.isEmpty &&
      moved.isEmpty &&
      renamed.isEmpty &&
      placeOrder.isEmpty;

  // corrupt or newer data falls back to the defaults
  factory DiningLayout.parse(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['v'] != diningLayoutVersion)
        return empty;
      return DiningLayout(
        order: [
          for (final id in (json['order'] as List<dynamic>? ?? const []))
            id as String,
        ],
        custom: {
          for (final entry in (json['custom'] as List<dynamic>? ?? const []))
            (entry as Map<String, dynamic>)['id'] as String:
                entry['name'] as String,
        },
        moved: {
          for (final entry
              in (json['moved'] as Map<String, dynamic>? ?? const {}).entries)
            int.parse(entry.key): entry.value as String,
        },
        renamed: {
          for (final entry
              in (json['renamed'] as Map<String, dynamic>? ?? const {}).entries)
            entry.key: entry.value as String,
        },
        placeOrder: {
          for (final entry
              in (json['places'] as Map<String, dynamic>? ?? const {}).entries)
            entry.key: [
              for (final id in entry.value as List<dynamic>) id as int,
            ],
        },
      );
    } on Object {
      return empty;
    }
  }

  // null when nothing differs from the defaults
  String? encode() {
    if (isEmpty) return null;
    return jsonEncode({
      'v': diningLayoutVersion,
      if (order.isNotEmpty) 'order': order,
      if (custom.isNotEmpty)
        'custom': [
          for (final e in custom.entries) {'id': e.key, 'name': e.value},
        ],
      if (moved.isNotEmpty)
        'moved': {for (final e in moved.entries) '${e.key}': e.value},
      if (renamed.isNotEmpty) 'renamed': renamed,
      if (placeOrder.isNotEmpty) 'places': placeOrder,
    });
  }

  DiningLayout _with({
    List<String>? order,
    Map<String, String>? custom,
    Map<int, String>? moved,
    Map<String, String>? renamed,
    Map<String, List<int>>? placeOrder,
  }) => DiningLayout(
    order: order ?? this.order,
    custom: custom ?? this.custom,
    moved: moved ?? this.moved,
    renamed: renamed ?? this.renamed,
    placeOrder: placeOrder ?? this.placeOrder,
  );

  DiningLayout rename(String id, String name, {required String defaultName}) {
    final trimmed = name.trim();
    if (custom.containsKey(id)) {
      if (trimmed.isEmpty) return this;
      return _with(custom: {...custom, id: trimmed});
    }
    final next = {...renamed};
    if (trimmed.isEmpty || trimmed == defaultName) {
      next.remove(id);
    } else {
      next[id] = trimmed;
    }
    return _with(renamed: next);
  }

  DiningLayout move(
    int placeId,
    String groupId, {
    required String defaultGroup,
  }) {
    final next = {...moved};
    if (groupId == defaultGroup) {
      next.remove(placeId);
    } else {
      next[placeId] = groupId;
    }
    return _with(moved: next);
  }

  // order is the full current order, stored only when it differs from the default
  DiningLayout reorder(List<String> current, List<String> defaults) {
    final same =
        current.length == defaults.length &&
        [for (var i = 0; i < current.length; i++) current[i] == defaults[i]]
            .every((e) => e);
    return _with(order: same ? const [] : current);
  }

  DiningLayout addCustom(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return this;
    var n = 1;
    while (custom.containsKey('custom-$n')) {
      n++;
    }
    return _with(custom: {...custom, 'custom-$n': trimmed});
  }

  DiningLayout removeCustom(String id) {
    if (!custom.containsKey(id)) return this;
    return _with(
      custom: {...custom}..remove(id),
      order: [...order]..remove(id),
      renamed: {...renamed}..remove(id),
      moved: {
        for (final e in moved.entries)
          if (e.value != id) e.key: e.value,
      },
      placeOrder: {...placeOrder}..remove(id),
    );
  }

  DiningLayout orderPlaces(String groupId, List<int> ids) {
    final next = {...placeOrder};
    if (ids.isEmpty) {
      next.remove(groupId);
    } else {
      next[groupId] = ids;
    }
    return _with(placeOrder: next);
  }

  // the group ids in display order, Other last
  List<String> groupOrder(List<GroupDef> defaults) {
    final known = [
      for (final g in defaults)
        if (g.id != otherGroupId) g.id,
      ...custom.keys,
    ];
    final ordered = <String>[
      for (final id in order)
        if (known.contains(id)) id,
    ];
    final seen = <String>{};
    return [
      for (final id in [...ordered, ...known])
        if (seen.add(id)) id,
      otherGroupId,
    ];
  }

  // every group with its places, empty ones included
  List<ResolvedGroup> resolve({
    required List<GroupDef> defaults,
    required String Function(int placeId) defaultGroupOf,
    required List<int> placeIds,
  }) {
    final ids = groupOrder(defaults);
    final defaultNames = {for (final g in defaults) g.id: g.name};
    final byGroup = {for (final id in ids) id: <int>[]};
    for (final place in placeIds) {
      final target = moved[place];
      final home = target != null && byGroup.containsKey(target)
          ? target
          : defaultGroupOf(place);
      byGroup[byGroup.containsKey(home) ? home : otherGroupId]!.add(place);
    }
    return [
      for (final id in ids)
        ResolvedGroup(
          id: id,
          name: custom[id] ?? renamed[id] ?? defaultNames[id] ?? id,
          isDefault: !custom.containsKey(id),
          placeIds: _sorted(byGroup[id]!, placeOrder[id]),
        ),
    ];
  }

  static List<int> _sorted(List<int> places, List<int>? manual) {
    if (manual == null) return places;
    return [
      for (final id in manual)
        if (places.contains(id)) id,
      for (final id in places)
        if (!manual.contains(id)) id,
    ];
  }
}
