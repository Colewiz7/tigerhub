/// Hand maintained configuration, bundled with the app.
///
/// These were validated by pydantic at backend boot (the project notes 8, decision 4).
/// They now ship as Flutter assets and are validated on first load instead. All
/// of them carry a `last_verified` date, and none of them is derivable from any
/// feed, which is exactly why they are hand maintained:
///
///   dining_categories  TigerCenter exposes no usable category at all
///   dining_groups      the Dining tab's areas, generated from the building table
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
    'dining_groups',
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

  // for screens that still draw before the config is loaded, as in tests
  static StaticConfig? get loadedOrNull => _instance;

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

  // --- dining groups ---

  // tests that override the files by hand may leave this one out
  Map<String, dynamic>? get _groups => _files['dining_groups'];

  List<({String id, String name})> get diningGroups => [
        for (final g in (_groups?['groups'] as List<dynamic>? ?? const []))
          (id: (g as Map<String, dynamic>)['id'] as String, name: g['name'] as String),
      ];

  // the places a hidden group covers, only for groups that list them
  Map<String, Set<int>> get diningGroupHideIds => {
        for (final g in (_groups?['groups'] as List<dynamic>? ?? const []))
          if ((g as Map<String, dynamic>)['hide_ids'] != null)
            g['id'] as String: {for (final id in g['hide_ids'] as List<dynamic>) id as int},
      };

  // every place in the table, for matching a chef by name
  List<({int id, String name})> get diningGroupPlaces => [
        for (final p in (_groups?['places'] as List<dynamic>? ?? const []))
          (id: (p as Map<String, dynamic>)['id'] as int, name: p['name'] as String),
      ];

  // a place the table doesnt know lands in other
  String diningGroupFor(int locationId) {
    for (final p in (_groups?['places'] as List<dynamic>? ?? const [])) {
      if ((p as Map<String, dynamic>)['id'] == locationId) return p['group'] as String;
    }
    return 'other';
  }

  // --- FD MealPlanner ---

  int get fdTenantId => file('fd_locations')['tenant_id'] as int? ?? 20;

  /// The FD entry for a TigerCenter dining id, or null when there is none.
  /// Three arena concessions have no TigerCenter counterpart and are listed
  /// under `unmapped` so a future reader knows they were considered.
  Map<String, dynamic>? fdLocationFor(int diningId) {
    for (final raw in file('fd_locations')['locations'] as List<dynamic>) {
      final entry = raw as Map<String, dynamic>;
      if (entry['dining_id'] == diningId) return entry;
    }
    return null;
  }

  // --- post offices ---

  List<Map<String, dynamic>> get postOffices => [
        for (final o in file('post_offices')['offices'] as List<dynamic>)
          o as Map<String, dynamic>,
      ];

  Map<String, dynamic>? office(String? id) {
    if (id == null) return null;
    for (final o in postOffices) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  // --- SHED ---

  List<Map<String, dynamic>> get shedSpaces => [
        for (final s in file('shed_hours')['spaces'] as List<dynamic>)
          s as Map<String, dynamic>,
      ];

  // --- housing ---

  Map<String, dynamic> get _housing => file('housing_areas');

  List<Map<String, dynamic>> get housingAreas => [
        for (final a in _housing['areas'] as List<dynamic>)
          a as Map<String, dynamic>,
      ];

  List<Map<String, dynamic>> get directDelivery => [
        for (final d in _housing['direct_delivery'] as List<dynamic>)
          d as Map<String, dynamic>,
      ];

  String? get housingSourceUrl => _housing['source_url'] as String?;

  Map<String, dynamic>? area(String id) {
    for (final a in housingAreas) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  Map<String, dynamic>? direct(String id) {
    for (final d in directDelivery) {
      if (d['id'] == id) return d;
    }
    return null;
  }

  /// Build the mailing address lines for an area.
  ///
  /// Line 2 is the student's own building/room designator. When it is not
  /// supplied, the area's documented format is shown as a placeholder rather
  /// than being invented. RIT runs a zone based system with no per hall street
  /// addresses (the project notes 7.9), so there is nothing to look up here.
  List<String>? addressFor(String areaId, String studentName, String? unit) {
    final delivered = direct(areaId);
    if (delivered != null) {
      return [
        studentName,
        '${delivered['street']}',
        '${delivered['city']} ${delivered['state']} ${delivered['zip']}',
      ];
    }

    final target = area(areaId);
    if (target == null) return null;
    final post = office(target['post_office'] as String?);
    if (post == null) return null;

    return [
      studentName,
      unit ?? '${target['line2_format']}',
      '${post['street']}',
      '${post['city']} ${post['state']} ${post['zip']}',
    ];
  }
}
