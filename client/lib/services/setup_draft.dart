/// What setup has collected, and the one place it is written.
///
/// Every answer is nullable and null means no change, so a step the reader
/// passes without choosing leaves their app exactly as it was. Nothing is
/// stored until [applyDraft] runs. The colour scheme is the one exception to
/// that, because it previews live, so a re-run restores it on Cancel.
library;

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../theme/dynamic_theme.dart';
import 'cache.dart';
import 'dashboard.dart';
import 'filter_profiles.dart';
import 'preferences.dart';

const dormSideGroupId = 'dorm_side';

String clubCardId(String organizerKey) => 'club-$organizerKey';

/// One toggle on the Your Today step.
class TodayRow {
  const TodayRow({required this.type, required this.label, this.club});

  final ModuleType type;
  final String label;

  /// The organizer key, for a Club events row.
  final String? club;

  String get key => club == null ? type.id : clubCardId(club!);
}

// the library setup offers, in the order it lists them
const List<ModuleType> _plainRows = [
  ModuleType.diningStatus,
  ModuleType.generalEvents,
  ModuleType.calendar,
  ModuleType.visitingChefs,
  ModuleType.academicDates,
  ModuleType.campusMap,
  ModuleType.shuttles,
  ModuleType.packagePickup,
  ModuleType.mailingAddress,
];

class SetupDraft extends ChangeNotifier {
  SetupDraft();

  /// A re-run starts from what is stored, so Save changes only what was edited.
  factory SetupDraft.prefilled({
    required Preferences prefs,
    required AppScheme scheme,
    required List<CardInstance> dashboard,
  }) {
    final draft = SetupDraft()
      .._scheme = scheme
      .._area = prefs.homeArea
      .._baseArea = prefs.homeArea
      .._baseSpots = {...prefs.pinnedDining}
      .._unit = prefs.homeUnit
      .._spots = {...prefs.pinnedDining}
      .._hideDormSide = prefs.isGroupHidden(dormSideGroupId)
      .._profile = activeProfile(prefs)?.id
      .._clubs = {
        for (final card in dashboard)
          if (card.type == ModuleType.clubEvents && !card.hidden && card.scope != null) card.scope!,
      };
    return draft;
  }

  AppScheme? _scheme;
  String? _baseArea;
  Set<String> _baseSpots = const {};
  String? _area;
  String? _unit;
  Set<String>? _spots;
  bool? _hideDormSide;
  String? _profile;
  Set<String>? _clubs;
  final Map<ModuleType, bool> _cards = {};
  final Map<String, String> _clubNames = {};

  AppScheme? get scheme => _scheme;
  String? get area => _area;
  String? get unit => _unit;
  Set<String>? get spots => _spots;
  bool? get hideDormSide => _hideDormSide;
  String? get profile => _profile;
  Set<String>? get clubs => _clubs;
  Map<ModuleType, bool> get cards => _cards;

  /// Display names for followed clubs, kept for the rows and the summary.
  String clubName(String key) => _clubNames[key] ?? key;

  void setScheme(AppScheme value) {
    _scheme = value;
    notifyListeners();
  }

  void setArea(String? value) {
    _area = value;
    notifyListeners();
  }

  void setUnit(String value) {
    _unit = value;
    notifyListeners();
  }

  void toggleSpot(String id) {
    final next = {...?_spots};
    if (!next.remove(id)) next.add(id);
    _spots = next;
    notifyListeners();
  }

  void setHideDormSide(bool value) {
    _hideDormSide = value;
    notifyListeners();
  }

  void setProfile(String id) {
    _profile = id;
    notifyListeners();
  }

  void followClub(String key, String name) {
    _clubNames[key] = name;
    _clubs = {...?_clubs, key};
    notifyListeners();
  }

  void unfollowClub(String key) {
    _clubs = {...?_clubs}..remove(key);
    notifyListeners();
  }

  void setCard(ModuleType type, bool on) {
    _cards[type] = on;
    notifyListeners();
  }

  /// A promotion only follows a new answer, so a re-run never brings back a
  /// card that was taken off Today.
  bool get homeIsNew => _area != null && _area != _baseArea;
  bool get spotsAreNew => (_spots?.isNotEmpty ?? false) && _baseSpots.isEmpty;

  /// Step answers, for the pinned button's label.
  bool get hasHome => _area != null;
  bool get hasSpots => (_spots?.isNotEmpty ?? false) || _hideDormSide == true;
  bool get hasEvents => _profile != null || (_clubs?.isNotEmpty ?? false);
  bool get hasToday => _cards.isNotEmpty;

  /// Anything answered at all, on any step.
  bool get hasAnything => _scheme != null || hasHome || hasSpots || hasEvents || hasToday;
}

/// The Your Today rows and the dashboard they produce.
class TodayPlan {
  TodayPlan._(this.rows, this.cards);

  /// Each row with whether it is on.
  final List<({TodayRow row, bool on})> rows;

  /// Every card, hidden ones kept in place, for Today to render and save.
  final List<CardInstance> cards;

  factory TodayPlan.of({
    required List<CardInstance> base,
    required SetupDraft draft,
  }) {
    bool shown(bool Function(CardInstance) test) => base.any((c) => !c.hidden && test(c));

    // clubs in the base that were unfollowed still get a row, so Save can hide them
    final clubKeys = <String>{
      for (final card in base)
        if (card.type == ModuleType.clubEvents && card.scope != null) card.scope!,
      ...?draft.clubs,
    };

    final rows = <({TodayRow row, bool on})>[];
    for (final type in _plainRows) {
      final onNow = shown((c) => c.type == type);
      final derived =
          onNow ||
          (type == ModuleType.diningStatus && draft.spotsAreNew) ||
          ((type == ModuleType.shuttles || type == ModuleType.packagePickup) && draft.homeIsNew);
      rows.add((row: TodayRow(type: type, label: moduleLabels[type]!), on: draft.cards[type] ?? derived));
    }
    final following = draft.clubs;
    for (final key in clubKeys.toList()..sort()) {
      final onNow = shown((c) => c.type == ModuleType.clubEvents && c.scope == key);
      rows.add((
        row: TodayRow(type: ModuleType.clubEvents, label: draft.clubName(key), club: key),
        on: following == null ? onNow : following.contains(key),
      ));
    }

    // only rows that changed touch a card, and nothing is ever deleted
    var cards = [...base];
    for (final entry in rows) {
      final row = entry.row;
      bool matches(CardInstance c) => c.type == row.type && (row.club == null || c.scope == row.club);
      final onNow = cards.any((c) => !c.hidden && matches(c));
      if (entry.on == onNow) continue;
      if (!entry.on) {
        cards = [for (final c in cards) matches(c) ? c.copyWith(hidden: true) : c];
        continue;
      }
      final at = cards.indexWhere(matches);
      if (at >= 0) {
        cards[at] = cards[at].copyWith(hidden: false);
        continue;
      }
      cards.add(_newCard(cards, row));
    }
    return TodayPlan._(rows, cards);
  }

  static CardInstance _newCard(List<CardInstance> cards, TodayRow row) {
    if (row.club != null) {
      return CardInstance(
        id: clubCardId(row.club!),
        type: ModuleType.clubEvents,
        size: defaultSizeFor(ModuleType.clubEvents),
        scope: row.club,
      );
    }
    var index = 0;
    while (cards.any((c) => c.id == '${row.type.id}-$index')) {
      index++;
    }
    return CardInstance(id: '${row.type.id}-$index', type: row.type, size: defaultSizeFor(row.type));
  }
}

/// Clubs the events feed knows, by organizer key, A to Z.
List<({String key, String name})> organizersOf(Iterable<CampusEvent> events) {
  final found = <String, String>{};
  for (final event in events) {
    final key = event.organizerKey;
    if (key == null || key.isEmpty) continue;
    found[key] = event.organizer ?? key;
  }
  return [
    for (final entry in found.entries) (key: entry.key, name: entry.value),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Writes every answer in the draft, then marks setup answered.
Future<void> applyDraft(
  SetupDraft draft, {
  required Preferences prefs,
  required SchemeController scheme,
}) async {
  final choice = draft.scheme;
  if (choice != null) await scheme.select(choice);

  if (draft.area != null) {
    await prefs.setHome(area: draft.area, unit: draft.unit ?? '');
  }

  final spots = draft.spots;
  if (spots != null) {
    for (final id in spots.difference(prefs.pinnedDining)) {
      await prefs.togglePinned(int.parse(id));
    }
    for (final id in prefs.pinnedDining.difference(spots).toList()) {
      await prefs.togglePinned(int.parse(id));
    }
  }
  final dorm = draft.hideDormSide;
  if (dorm != null) await prefs.setGroupHidden(dormSideGroupId, dorm);

  final profile = draft.profile == null ? null : profileById(draft.profile!);
  if (profile != null) {
    await prefs.applyProfile(profile.hide, profile.boost, keywordsEnabled: profile.keywordsEnabled);
  }

  // Today changes only when an answer reaches it
  if (draft.hasToday || draft.clubs != null || draft.hasSpots || draft.hasHome) {
    final base = await DashboardStore.load();
    final plan = TodayPlan.of(base: base, draft: draft);
    await DashboardStore.save(plan.cards, notify: true);
  }

  await prefs.markSetupSeen();
}

// the stored keys that only someone who has used the app would have
const _usedKeys = [
  'housing_area',
  'dashboard_v2',
  'cards',
  'cards_hidden',
  'color_scheme',
  'pinned_dining',
  'hidden_dining',
  'dining_layout',
  'campus_layout',
  'muted_organizers',
  'hide_keywords',
  'boost_keywords',
  'keyword_rules_enabled',
  'diet_filters',
  'avoid_allergens',
  'today_smart_order',
];

/// Whether this phone already holds someone's settings. Setup never marked
/// them as seen, so they get the one-time sheet instead of the full flow.
Future<bool> hasExistingData() async {
  for (final key in _usedKeys) {
    if ((await ResponseCache.instance.readOrder(key)).isNotEmpty) return true;
  }
  return false;
}
