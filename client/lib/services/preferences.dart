/// User preferences.
///
/// All of it lives in shared_preferences, same as card order. No database:
/// this is a handful of string lists per device.
///
/// Filtering is entirely client side. The API keeps returning everything and
/// stays stateless about users.
library;

import 'package:flutter/foundation.dart';

import 'cache.dart';

/// Keyword defaults, all editable.
const List<String> defaultHideKeywords = [
  'tutoring',
  'info session',
  'workshop',
  'seminar',
  'career fair',
  'club fair',
  'recruitment',
  'bible study',
  'mass',
  'worship',
];

const List<String> defaultBoostKeywords = [
  'free',
  'food',
  'ice cream',
  'pizza',
  'game',
  'tournament',
  'trivia',
  'movie',
];

class Preferences extends ChangeNotifier {
  Preferences._();

  static final Preferences instance = Preferences._();

  static const _mutedKey = 'muted_organizers';
  static const _hideKey = 'hide_keywords';
  static const _boostKey = 'boost_keywords';
  static const _keywordsEnabledKey = 'keyword_rules_enabled';
  static const _pinnedKey = 'pinned_dining';
  static const _dietKey = 'diet_filters';
  static const _avoidKey = 'avoid_allergens';

  Set<String> _muted = {};
  Set<String> _pinned = {};
  Set<String> _diet = {};
  Set<String> _avoid = {};
  List<String> _hide = defaultHideKeywords;
  List<String> _boost = defaultBoostKeywords;
  bool _keywordRulesEnabled = true;
  bool _loaded = false;

  bool get loaded => _loaded;
  Set<String> get mutedOrganizers => _muted;

  /// Dining location ids, as strings. Pinned locations sort to the top.
  Set<String> get pinnedDining => _pinned;

  /// Dietary tags to keep, for example Vegan. Empty means no filter.
  Set<String> get dietFilters => _diet;

  /// Allergens to flag. Dishes are marked, never silently removed, because a
  /// missing dish is indistinguishable from a dish that was never published.
  Set<String> get avoidAllergens => _avoid;
  List<String> get hideKeywords => _hide;
  List<String> get boostKeywords => _boost;
  bool get keywordRulesEnabled => _keywordRulesEnabled;

  Future<void> load() async {
    final cache = ResponseCache.instance;
    _muted = (await cache.readOrder(_mutedKey)).toSet();
    _pinned = (await cache.readOrder(_pinnedKey)).toSet();
    _diet = (await cache.readOrder(_dietKey)).toSet();
    _avoid = (await cache.readOrder(_avoidKey)).toSet();

    // An empty stored list is meaningful (the user cleared it), so absence has
    // to be distinguishable from emptiness. A stored marker entry does that.
    final hide = await cache.readOrder(_hideKey);
    final boost = await cache.readOrder(_boostKey);
    _hide = hide.isEmpty ? defaultHideKeywords : _stripMarker(hide);
    _boost = boost.isEmpty ? defaultBoostKeywords : _stripMarker(boost);

    final flags = await cache.readOrder(_keywordsEnabledKey);
    _keywordRulesEnabled = flags.isEmpty || flags.first == 'true';

    _loaded = true;
    notifyListeners();
  }

  static const _emptyMarker = '__empty__';

  static List<String> _stripMarker(List<String> values) =>
      values.where((v) => v != _emptyMarker).toList();

  static List<String> _withMarker(List<String> values) =>
      values.isEmpty ? const [_emptyMarker] : values;

  Future<void> setMuted(String organizerKey, bool muted) async {
    if (muted) {
      _muted = {..._muted, organizerKey};
    } else {
      _muted = {..._muted}..remove(organizerKey);
    }
    notifyListeners();
    await ResponseCache.instance.writeOrder(_mutedKey, _muted.toList());
  }

  bool isPinned(int locationId) => _pinned.contains('$locationId');

  Future<void> toggleDiet(String tag) async {
    _diet = _diet.contains(tag) ? ({..._diet}..remove(tag)) : {..._diet, tag};
    notifyListeners();
    await ResponseCache.instance.writeOrder(_dietKey, _diet.toList());
  }

  Future<void> toggleAvoid(String allergen) async {
    _avoid = _avoid.contains(allergen)
        ? ({..._avoid}..remove(allergen))
        : {..._avoid, allergen};
    notifyListeners();
    await ResponseCache.instance.writeOrder(_avoidKey, _avoid.toList());
  }

  Future<void> togglePinned(int locationId) async {
    final key = '$locationId';
    _pinned = _pinned.contains(key)
        ? ({..._pinned}..remove(key))
        : {..._pinned, key};
    notifyListeners();
    await ResponseCache.instance.writeOrder(_pinnedKey, _pinned.toList());
  }

  Future<void> clearMutes() async {
    _muted = {};
    notifyListeners();
    await ResponseCache.instance.writeOrder(_mutedKey, const []);
  }

  Future<void> setHideKeywords(List<String> values) async {
    _hide = _clean(values);
    notifyListeners();
    await ResponseCache.instance.writeOrder(_hideKey, _withMarker(_hide));
  }

  Future<void> setBoostKeywords(List<String> values) async {
    _boost = _clean(values);
    notifyListeners();
    await ResponseCache.instance.writeOrder(_boostKey, _withMarker(_boost));
  }

  /// Apply a preset in one go, so switching taste is one tap rather than
  /// twenty edits.
  Future<void> applyProfile(List<String> hide, List<String> boost,
      {required bool keywordsEnabled}) async {
    _hide = _clean(hide);
    _boost = _clean(boost);
    _keywordRulesEnabled = keywordsEnabled;
    notifyListeners();
    final cache = ResponseCache.instance;
    await cache.writeOrder(_hideKey, _withMarker(_hide));
    await cache.writeOrder(_boostKey, _withMarker(_boost));
    await cache.writeOrder(_keywordsEnabledKey, [keywordsEnabled ? 'true' : 'false']);
  }

  Future<void> setKeywordRulesEnabled(bool enabled) async {
    _keywordRulesEnabled = enabled;
    notifyListeners();
    await ResponseCache.instance
        .writeOrder(_keywordsEnabledKey, [enabled ? 'true' : 'false']);
  }

  static List<String> _clean(List<String> values) {
    final seen = <String>{};
    return [
      for (final raw in values)
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase()))
          raw.trim().toLowerCase(),
    ];
  }

  /// Test hook. Resets in-memory state without touching storage.
  @visibleForTesting
  void resetForTests() {
    _muted = {};
    _pinned = {};
    _diet = {};
    _avoid = {};
    _hide = defaultHideKeywords;
    _boost = defaultBoostKeywords;
    _keywordRulesEnabled = true;
    _loaded = false;
  }
}
