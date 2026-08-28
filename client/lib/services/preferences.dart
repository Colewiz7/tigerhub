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

  Set<String> _muted = {};
  List<String> _hide = defaultHideKeywords;
  List<String> _boost = defaultBoostKeywords;
  bool _keywordRulesEnabled = true;
  bool _loaded = false;

  bool get loaded => _loaded;
  Set<String> get mutedOrganizers => _muted;
  List<String> get hideKeywords => _hide;
  List<String> get boostKeywords => _boost;
  bool get keywordRulesEnabled => _keywordRulesEnabled;

  Future<void> load() async {
    final cache = ResponseCache.instance;
    _muted = (await cache.readOrder(_mutedKey)).toSet();

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
    _hide = defaultHideKeywords;
    _boost = defaultBoostKeywords;
    _keywordRulesEnabled = true;
    _loaded = false;
  }
}
