/// Campus tab layout stored as diffs from the shipped sections.
library;

import 'dart:convert';

import '../models/api_models.dart';

const campusLayoutVersion = 1;

/// The office id [areas] assigns to [homeArea], null while home is unknown.
String? myPostOffice(List<PostOffice> offices, List<HousingArea> areas, String? homeArea) {
  final id = postOfficeFor(areas, homeArea);
  return offices.any((o) => o.id == id) ? id : null;
}

/// My side by default, both when home is unknown or the reader asked for all.
List<PostOffice> officesToShow(List<PostOffice> offices, {required String? mine, required CampusLayout layout}) {
  final scoped = mine == null || layout.allOffices ? offices : [for (final o in offices) if (o.id == mine) o];
  return [for (final o in scoped) if (!layout.hiddenOffices.contains(o.id)) o];
}

/// The offices the reader hid, whichever side they are on.
List<PostOffice> hiddenOffices(List<PostOffice> offices, CampusLayout layout) => [
  for (final o in offices) if (layout.hiddenOffices.contains(o.id)) o,
];

/// The nav rows in their shipped order.
const campusSectionIds = ['mail', 'find', 'dates', 'safety', 'links', 'rec', 'shed'];

const safetySectionId = 'safety';

class CampusLayout {
  const CampusLayout({
    this.order = const [],
    this.hidden = const {},
    this.hiddenOffices = const {},
    this.hiddenFacilities = const {},
    this.allOffices = false,
    this.safetyAsked = false,
  });

  static const empty = CampusLayout();

  // section ids, only when the order differs from the default
  final List<String> order;
  // nav rows the reader hid
  final Set<String> hidden;
  // post office ids
  final Set<String> hiddenOffices;
  // gym and pool facility names
  final Set<String> hiddenFacilities;
  // false is the default: the post office on your side, both when home is unknown
  final bool allOffices;
  // Safety is hidden only after one confirmation, and that is asked once
  final bool safetyAsked;

  bool get isEmpty =>
      order.isEmpty &&
      hidden.isEmpty &&
      hiddenOffices.isEmpty &&
      hiddenFacilities.isEmpty &&
      !allOffices &&
      !safetyAsked;

  // anything the Hidden controls can bring back
  bool get hasHidden => hidden.isNotEmpty || hiddenOffices.isNotEmpty || hiddenFacilities.isNotEmpty;

  // corrupt or newer data falls back to the defaults
  factory CampusLayout.parse(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['v'] != campusLayoutVersion) {
        return empty;
      }
      List<String> strings(String key) => [
        for (final id in (json[key] as List<dynamic>? ?? const [])) id as String,
      ];
      return CampusLayout(
        order: strings('order'),
        hidden: strings('hidden').toSet(),
        hiddenOffices: strings('offices').toSet(),
        hiddenFacilities: strings('facilities').toSet(),
        allOffices: json['all_offices'] as bool? ?? false,
        safetyAsked: json['safety_asked'] as bool? ?? false,
      );
    } on Object {
      return empty;
    }
  }

  // null when nothing differs from the defaults
  String? encode() {
    if (isEmpty) return null;
    return jsonEncode({
      'v': campusLayoutVersion,
      if (order.isNotEmpty) 'order': order,
      if (hidden.isNotEmpty) 'hidden': hidden.toList(),
      if (hiddenOffices.isNotEmpty) 'offices': hiddenOffices.toList(),
      if (hiddenFacilities.isNotEmpty) 'facilities': hiddenFacilities.toList(),
      if (allOffices) 'all_offices': true,
      if (safetyAsked) 'safety_asked': true,
    });
  }

  CampusLayout _with({
    List<String>? order,
    Set<String>? hidden,
    Set<String>? hiddenOffices,
    Set<String>? hiddenFacilities,
    bool? allOffices,
    bool? safetyAsked,
  }) => CampusLayout(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    hiddenOffices: hiddenOffices ?? this.hiddenOffices,
    hiddenFacilities: hiddenFacilities ?? this.hiddenFacilities,
    allOffices: allOffices ?? this.allOffices,
    safetyAsked: safetyAsked ?? this.safetyAsked,
  );

  // every section id in display order, hidden ones included
  List<String> sectionOrder([List<String> defaults = campusSectionIds]) {
    final seen = <String>{};
    return [
      for (final id in [...order.where(defaults.contains), ...defaults])
        if (seen.add(id)) id,
    ];
  }

  // the ids shown in the nav, in display order
  List<String> visibleSections([List<String> defaults = campusSectionIds]) => [
    for (final id in sectionOrder(defaults))
      if (!hidden.contains(id)) id,
  ];

  // swaps with the nearest visible neighbour, so the move is always seen
  CampusLayout moveSection(String id, int step, [List<String> defaults = campusSectionIds]) {
    final current = sectionOrder(defaults);
    final visible = visibleSections(defaults);
    final at = visible.indexOf(id);
    final to = at + step;
    if (at < 0 || to < 0 || to >= visible.length) return this;
    final next = [...current];
    final a = next.indexOf(id);
    final b = next.indexOf(visible[to]);
    next[a] = visible[to];
    next[b] = id;
    final same = [for (var i = 0; i < next.length; i++) next[i] == defaults[i]].every((e) => e);
    return _with(order: same ? const [] : next);
  }

  CampusLayout hideSection(String id) => hidden.contains(id) ? this : _with(hidden: {...hidden, id});

  CampusLayout showSection(String id) => hidden.contains(id) ? _with(hidden: {...hidden}..remove(id)) : this;

  CampusLayout hideOffice(String id) => hiddenOffices.contains(id) ? this : _with(hiddenOffices: {...hiddenOffices, id});

  CampusLayout showOffice(String id) => hiddenOffices.contains(id) ? _with(hiddenOffices: {...hiddenOffices}..remove(id)) : this;

  CampusLayout hideFacility(String name) => hiddenFacilities.contains(name) ? this : _with(hiddenFacilities: {...hiddenFacilities, name});

  CampusLayout showFacility(String name) =>
      hiddenFacilities.contains(name) ? _with(hiddenFacilities: {...hiddenFacilities}..remove(name)) : this;

  CampusLayout withAllOffices(bool value) => _with(allOffices: value);

  CampusLayout markSafetyAsked() => safetyAsked ? this : _with(safetyAsked: true);

  // the order, the post office choice and the Safety note stay as they are
  CampusLayout unhideAll() => _with(hidden: const {}, hiddenOffices: const {}, hiddenFacilities: const {});
}
