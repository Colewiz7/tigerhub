/// The Today dashboard as instances of module types.
///
/// Stage one of `docs/modular-dashboard-spec.md`. A card stops being a bare
/// string id and becomes an **instance**: a stable id of its own, a module
/// type, a scope, a size, and a position. That is what lets the same type
/// appear twice with different scopes, which is the whole point of "modular"
/// and the thing the old four fixed strings could not express.
///
/// Deliberately not a freeform canvas. The spec is explicit: pixel resizing and
/// arbitrary placement create holes, fragile phone layouts and awkward keyboard
/// behaviour. Modules pick from a small set of footprints and the app packs
/// them in reading order.
///
/// **Migration matters more than the model here.** Anyone using the app already
/// has four cards in an order they chose, some possibly hidden. That has to
/// survive, unchanged and in the same order, or the feature costs them their
/// setup to gain a capability they did not ask for yet.
library;

import 'dart:convert';

import 'cache.dart';

/// The module types the dashboard can place.
///
/// General and club events share a renderer but are separate types, because
/// "show me one club" is the common task and should not require going through
/// a scope editor to reach.
enum ModuleType {
  diningStatus('dining_status'),
  generalEvents('general_events'),
  clubEvents('club_events'),
  calendar('calendar'),
  visitingChefs('visiting_chefs'),
  mailingAddress('mailing_address'),
  facilityHours('facility_hours'),
  campusMap('campus_map');

  const ModuleType(this.id);

  final String id;

  static ModuleType? byId(String id) {
    for (final type in values) {
      if (type.id == id) return type;
    }
    return null;
  }
}

/// Footprints, not pixels. A size states priority; the packer decides the rest.
enum CardSize {
  /// One column, one height unit. Answers exactly one question.
  compact('compact'),

  /// One column, two height units. The density cards have today.
  standard('standard'),

  /// Two columns. A calendar, the map, or grouped columns.
  wide('wide');

  const CardSize(this.id);

  final String id;

  /// How many columns this footprint asks for.
  int get columns => this == CardSize.wide ? 2 : 1;

  static CardSize? byId(String id) {
    for (final size in values) {
      if (size.id == id) return size;
    }
    return null;
  }
}

/// Which sizes each module can actually carry.
///
/// A size is only offered where the content stays useful in it. Mailing
/// Address has nothing meaningful to say in one line, and the map needs the
/// width, so neither offers every size.
const Map<ModuleType, List<CardSize>> supportedSizes = {
  ModuleType.diningStatus: [CardSize.compact, CardSize.standard],
  ModuleType.generalEvents: [
    CardSize.compact,
    CardSize.standard,
    CardSize.wide,
  ],
  ModuleType.clubEvents: [CardSize.compact, CardSize.standard, CardSize.wide],
  ModuleType.calendar: [CardSize.standard, CardSize.wide],
  ModuleType.visitingChefs: [CardSize.compact, CardSize.standard],
  ModuleType.mailingAddress: [CardSize.standard],
  ModuleType.facilityHours: [CardSize.compact, CardSize.standard],
  ModuleType.campusMap: [CardSize.wide],
};

/// One placed card.
class CardInstance {
  const CardInstance({
    required this.id,
    required this.type,
    this.size = CardSize.standard,
    this.scope,
    this.hidden = false,
  });

  /// Stable and separate from the type, so two instances of one type stay
  /// distinguishable when their scopes differ.
  final String id;

  final ModuleType type;
  final CardSize size;

  /// What this instance is narrowed to: a dining category, an organizer key, a
  /// facility. Null means the module's default breadth.
  final String? scope;

  final bool hidden;

  CardInstance copyWith({
    CardSize? size,
    String? scope,
    bool? hidden,
    bool clearScope = false,
  }) => CardInstance(
    id: id,
    type: type,
    size: size ?? this.size,
    scope: clearScope ? null : (scope ?? this.scope),
    hidden: hidden ?? this.hidden,
  );

  /// Falls back rather than throwing: a size this module does not support, or
  /// a type from a newer build, must not cost someone their whole dashboard.
  static CardInstance? fromJson(Map<String, dynamic> json) {
    final type = ModuleType.byId(json['type'] as String? ?? '');
    if (type == null) return null;

    final size = CardSize.byId(json['size'] as String? ?? '');
    final allowed = supportedSizes[type] ?? const [CardSize.standard];

    return CardInstance(
      id: json['id'] as String? ?? '${type.id}-0',
      type: type,
      size: size != null && allowed.contains(size) ? size : allowed.first,
      scope: json['scope'] as String?,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.id,
    'size': size.id,
    if (scope != null) 'scope': scope,
    if (hidden) 'hidden': true,
  };
}

/// What each module is called and which glyph identifies it, for the card
/// library and the inspector. Kept beside the type rather than in the widget
/// layer so the Add Card flow and the renderer cannot disagree.
const Map<ModuleType, String> moduleLabels = {
  ModuleType.diningStatus: 'Dining',
  ModuleType.generalEvents: 'Events',
  ModuleType.clubEvents: 'Club events',
  ModuleType.calendar: 'Calendar',
  ModuleType.visitingChefs: 'Visiting Chefs',
  ModuleType.mailingAddress: 'Mailing Address',
  ModuleType.facilityHours: 'Facility hours',
  ModuleType.campusMap: 'Campus map',
};

/// The four cards the app shipped with, as instances.
const List<CardInstance> defaultDashboard = [
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs),
  CardInstance(id: 'housing-0', type: ModuleType.mailingAddress),
];

/// The old string ids, mapped to what they became.
const Map<String, ({String id, ModuleType type})> _legacyCards = {
  'dining': (id: 'dining-0', type: ModuleType.diningStatus),
  'events': (id: 'events-0', type: ModuleType.generalEvents),
  'chefs': (id: 'chefs-0', type: ModuleType.visitingChefs),
  'housing': (id: 'housing-0', type: ModuleType.mailingAddress),
};

/// Rebuild a dashboard from the pre-instance format.
///
/// Order and hidden state are preserved exactly. Anything unrecognised is
/// dropped rather than guessed at, and anything missing is appended in the
/// default order so a partial saved list still yields a complete dashboard.
List<CardInstance> migrateLegacy(List<String> order, List<String> hidden) {
  final out = <CardInstance>[];
  final placed = <String>{};

  for (final legacy in order) {
    final mapped = _legacyCards[legacy];
    if (mapped == null || !placed.add(legacy)) continue;
    out.add(
      CardInstance(
        id: mapped.id,
        type: mapped.type,
        hidden: hidden.contains(legacy),
      ),
    );
  }

  for (final entry in _legacyCards.entries) {
    if (placed.contains(entry.key)) continue;
    out.add(
      CardInstance(
        id: entry.value.id,
        type: entry.value.type,
        hidden: hidden.contains(entry.key),
      ),
    );
  }

  return out;
}

/// Reads and writes the dashboard, migrating the old format on first load.
class DashboardStore {
  const DashboardStore._();

  static const _key = 'dashboard_v2';
  static const _legacyOrderKey = 'cards';
  static const _legacyHiddenKey = 'cards_hidden';

  static Future<List<CardInstance>> load() async {
    final cache = ResponseCache.instance;

    final saved = await cache.readOrder(_key);
    if (saved.isNotEmpty) {
      final restored = <CardInstance>[];
      for (final entry in saved) {
        try {
          final decoded = jsonDecode(entry);
          if (decoded is Map<String, dynamic>) {
            final instance = CardInstance.fromJson(decoded);
            if (instance != null) restored.add(instance);
          }
        } catch (_) {
          // One unreadable entry must not take the rest of the dashboard.
        }
      }
      if (restored.isNotEmpty) return restored;
    }

    // Nothing saved in the new format: bring the old one across.
    final order = await cache.readOrder(_legacyOrderKey);
    final hidden = await cache.readOrder(_legacyHiddenKey);
    if (order.isEmpty && hidden.isEmpty) return defaultDashboard;

    // Written back, not just returned. Migrating on every launch would work,
    // but it would leave the old keys authoritative forever and give the new
    // fields, scope and size, nowhere to live until the user happened to edit
    // something.
    final migrated = migrateLegacy(order, hidden);
    await save(migrated);
    return migrated;
  }

  static Future<void> save(List<CardInstance> cards) => ResponseCache.instance
      .writeOrder(_key, [for (final card in cards) jsonEncode(card.toJson())]);
}
