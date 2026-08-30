/// Hand maintained configuration, bundled with the app.
///
/// These were validated by pydantic at backend boot (CLAUDE.md 8, decision 4).
/// They now ship as Flutter assets and are validated on first load instead. All
/// of them carry a `last_verified` date, and none of them is derivable from any
/// feed, which is exactly why they are hand maintained:
///
///   dining_categories  TigerCenter exposes no usable category at all
///   post_offices       RIT publishes hours per service, as prose, on a page
///   housing_areas      zone based mail, no per hall addresses exist
///   shed_hours         the make.rit.edu hours feed is broken (7.5)
///   fd_locations       FD's location ids are unrelated to TigerCenter's
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class StaticConfig {
  StaticConfig._(this._files);

  final Map<String, Map<String, dynamic>> _files;

  static StaticConfig? _instance;

  static const List<String> _names = [
    'dining_categories',
    'post_offices',
    'housing_areas',
    'shed_hours',
    'fd_locations',
  ];

  static Future<StaticConfig> load() async {
    if (_instance != null) return _instance!;
    final files = <String, Map<String, dynamic>>{};
    for (final name in _names) {
      final raw = await rootBundle.loadString('assets/config/$name.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('config asset $name.json is not a JSON object');
      }
      if (decoded['last_verified'] is! String) {
        // Every hand maintained file must say when a human last checked it,
        // otherwise there is no way to tell config from folklore.
        throw StateError('config asset $name.json has no last_verified date');
      }
      files[name] = decoded;
    }
    return _instance = StaticConfig._(files);
  }

  static void overrideForTesting(Map<String, Map<String, dynamic>> files) =>
      _instance = StaticConfig._(files);

  /// Only valid after [load]. Callers on the read path always run after the
  /// first load, so this avoids threading the instance through every
  /// projection signature.
  static StaticConfig get instance =>
      _instance ?? (throw StateError('StaticConfig.load() has not run'));

  Map<String, dynamic> file(String name) =>
      _files[name] ?? (throw StateError('config asset $name not loaded'));

  // --- dining categories ---

  List<Map<String, dynamic>> get diningCategories => [
        for (final c in file('dining_categories')['categories'] as List<dynamic>)
          c as Map<String, dynamic>,
      ];

  String get defaultDiningCategory =>
      file('dining_categories')['default_category'] as String? ?? 'other';

  String categoryFor(int locationId) =>
      (file('dining_categories')['assignments']
          as Map<String, dynamic>)['$locationId'] as String? ??
      defaultDiningCategory;

  Map<String, dynamic>? _category(String id) {
    for (final c in diningCategories) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  String categoryName(String id) =>
      _category(id)?['name'] as String? ?? 'Everything else';

  int categoryOrder(String id) => _category(id)?['order'] as int? ?? 999;
}
