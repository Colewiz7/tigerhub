/// Campus points of interest from maps.rit.edu.
///
/// Ported from `backend/app/scrapers/campus_places.py`.
///
/// Answers "where is the nearest water fountain", which is the kind of question
/// the official map makes surprisingly hard.
///
/// The useful data sits at `subLocations[].locations[].properties` and carries a
/// building abbreviation, a floor, a room number and a human note like "Corner
/// of hallway, next to bathrooms".
///
/// The full taxonomy is 11 categories and about 50 sub-categories. Only the ones
/// students actually need are fetched: the rest are parking tiers, building
/// types and staff facilities that would be noise.
///
/// This is physical infrastructure and changes rarely, so it runs twice a day.
library;

import '../turbo_stream.dart';
import '../upstream.dart';

const String campusPlacesSource = 'campus_places';
const String campusPlacesUrl = 'https://maps.rit.edu/categories/{id}.data';

/// Sub-category id to the key it is stored under, and its display name. Ids
/// came from decoding the category tree.
const Map<int, (String, String)> placeKinds = {
  270: ('water', 'Water fountains'),
  195: ('ev_charge', 'EV charging'),
  131: ('blue_light', 'Blue light phones'),
  135: ('aed', 'Defibrillators'),
  159: ('restroom_all_gender', 'All-gender restrooms'),
  171: ('restroom_accessible', 'Accessible restrooms'),
  151: ('atm', 'ATMs'),
  175: ('changing_table', 'Diaper changing stations'),
  139: ('entrance_accessible', 'Accessible entrances'),
  123: ('bus_stop', 'Bus stops'),
  119: ('bike_rack', 'Bike racks'),
  232: ('reload', 'Tiger Spend reload stations'),
  199: ('time_clock', 'Workday time clocks'),
  527: ('printer', 'Printers'),
  236: ('study_area', 'Study areas'),
  211: ('computer_lab', 'Computer labs'),
  528: ('connection_hub', 'Connection Hub'),
  279: ('lactation', 'Lactation rooms'),
  87: ('vending', 'Vending machines'),
  83: ('convenience', 'Convenience stores'),
};

/// One request per parent category returns every sub it contains, so a handful
/// of requests cover all twelve place kinds rather than twelve.
///
/// **3, 11 and 47 are here for their outlines, not for pins.** Between them
/// they carry the shape of campus:
///
///     3   Buildings   152 polygons, with abbreviations, grouped into
///                     academic, residential, green, admin and athletic
///     11  Parking      62 polygons, the lots
///     47  Other        17 polygons, including quads and courtyards
///
/// Without them the map drew the twenty buildings that happened to appear
/// inside the other categories, mostly LEED ones from Sustainability, so campus
/// was a scatter of dots on an empty field rather than a map.
///
/// Category 3's abbreviations are also what event placement needs: the spec
/// allows a pin only on an exact building match, and there was almost nothing
/// to match against before.
///
/// Their point features are ignored, because those kinds are not in
/// [placeKinds]; only the geometry comes through.
/// 39 is Employees, which is where the Workday time clocks live. It is the
/// only parent here fetched purely for a student-facing kind rather than for
/// outlines or a cluster of kinds, and it carries 63 clocks.
const List<int> placeParents = [3, 11, 47, 35, 19, 27, 23, 15, 7, 39];

/// What this source currently asks maps.rit.edu for.
///
/// Both halves matter and both have bitten. A kind registered without its
/// parent is never fetched; a parent fetched without the kind registered has
/// its points parsed and dropped, which is what hid seven categories that were
/// already on the wire. Either change alters what a scrape returns without
/// touching its schedule, so the stored snapshot has to be invalidated by the
/// request set rather than by age alone.
String get campusPlacesFingerprint {
  final parents = [...placeParents]..sort();
  final kinds = placeKinds.keys.toList()..sort();
  return 'parents:${parents.join(",")}|kinds:${kinds.join(",")}';
}

String? _trimmed(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

/// Pull the points out of one parent category payload, keyed by sub id.
///
/// A payload carries every sub-category the parent contains, and each group
/// names itself through `menu.id`. Grouping on that rather than on position
/// means a reordering upstream cannot silently mix water fountains into ATMs.
///
/// Located by key rather than by a fixed path, because the surrounding route
/// structure is RIT's to change and the leaf shape is what matters.
Map<int, List<Map<String, dynamic>>> parseCampusPlaces(String raw) {
  Object? decoded;
  try {
    decoded = decodeTurboStream(raw);
  } on TurboStreamError {
    return {};
  }

  final out = <int, List<Map<String, dynamic>>>{};

  for (final group in findAll(decoded, 'subLocations')) {
    if (group is! List) continue;
    for (final sub in group) {
      if (sub is! Map<String, dynamic>) continue;
      final menu = sub['menu'];
      final subId = menu is Map<String, dynamic> ? menu['id'] : null;
      if (subId is! int || !placeKinds.containsKey(subId)) continue;

      final kindName = placeKinds[subId]!.$2;
      final places = out.putIfAbsent(subId, () => []);
      final seen = {for (final p in places) p['id'] as int};

      for (final location in sub['locations'] as List<dynamic>? ?? const []) {
        if (location is! Map<String, dynamic>) continue;
        final props = location['properties'];
        if (props is! Map<String, dynamic>) continue;

        final placeId = props['id'];
        final name = props['name'];
        if (placeId is! int || name is! String) continue;
        if (!seen.add(placeId)) continue;

        places.add({
          'id': placeId,
          'kind_name': kindName,
          'name': name.trim(),
          'building': _trimmed(props['abbreviation']),
          'building_no': _trimmed(props['buildingNumber']),
          'floor': _trimmed(props['floorLevel']),
          'room': _trimmed(props['roomNumber']),
          'note': _trimmed(props['descShort']),
          'mdo_id': props['mdo_id'] is int ? props['mdo_id'] : null,
        });
      }
    }
  }

  return out;
}

/// Decode the GeoJSON that [parseCampusPlaces] deliberately leaves out.
///
/// This is a separate projection so adding a map cannot change the
/// parity-tested place contract used by the existing lists and sheets.
List<Map<String, dynamic>> parseCampusMapFeatures(String raw) {
  Object? decoded;
  try {
    decoded = decodeTurboStream(raw);
  } on TurboStreamError {
    return [];
  }

  final out = <Map<String, dynamic>>[];
  final seen = <String>{};

  for (final group in findAll(decoded, 'subLocations')) {
    if (group is! List) continue;
    for (final sub in group) {
      if (sub is! Map<String, dynamic>) continue;
      final menu = sub['menu'];
      final subId = menu is Map<String, dynamic> ? menu['id'] : null;
      final placeKind = subId is int ? placeKinds[subId] : null;
      for (final location in sub['locations'] as List<dynamic>? ?? const []) {
        if (location is! Map<String, dynamic>) continue;
        final props = location['properties'];
        final geometry = location['geometry'];
        if (props is! Map<String, dynamic> ||
            geometry is! Map<String, dynamic>) {
          continue;
        }

        final id = props['id'];
        final name = props['name'];
        final type = geometry['type'];
        final coordinates = geometry['coordinates'];
        if (id is! int ||
            name is! String ||
            type is! String ||
            coordinates is! List) {
          continue;
        }
        if (!const {'Point', 'Polygon', 'MultiPolygon'}.contains(type)) {
          continue;
        }

        // Point features are the twelve student-facing place categories. A
        // parent payload also carries polygon geometry for buildings and
        // campus structures outside those categories. The old parser applied
        // the place-category allowlist to every geometry type, which silently
        // discarded every outline and left the map as dots on an empty field.
        if (type == 'Point' && placeKind == null) continue;
        final kind = placeKind?.$1 ?? '_campus';

        // Backdrop geometry keeps the '_campus' kind the renderer looks for,
        // but names itself after the sub-category it came from: "Academic
        // Building", "General Parking", "Quads And Courtyards". A parking lot
        // and a lecture hall are both backdrop, and being able to tell them
        // apart is what lets them be drawn differently later.
        final subName = menu is Map<String, dynamic> ? menu['name'] : null;
        final kindName = placeKind?.$2 ??
            (subName is String && subName.trim().isNotEmpty
                ? subName.trim()
                : 'Campus structure');

        // The same building geometry appears in several parent payloads.
        if (!seen.add('$kind:$id')) continue;

        out.add({
          'id': id,
          'kind': kind,
          'kind_name': kindName,
          'name': name.trim(),
          'building': _trimmed(props['abbreviation']),
          'floor': _trimmed(props['floorLevel']),
          'room': _trimmed(props['roomNumber']),
          'note': _trimmed(props['descShort']),
          'geometry': {'type': type, 'coordinates': coordinates},
        });
      }
    }
  }
  return out;
}

Future<Map<String, dynamic>> scrapeCampusPlaces(Upstream http) async {
  final byKind = <String, List<Map<String, dynamic>>>{};
  final mapFeatures = <Map<String, dynamic>>[];
  final seenMapFeatures = <String>{};
  final failures = <int>[];

  // Sequential on purpose. Six categories at roughly 250 KB each is small, but
  // firing them in parallel at someone else's map server is rude.
  for (final parent in placeParents) {
    try {
      final raw = await http.getText(
        campusPlacesUrl.replaceFirst('{id}', '$parent'),
      );
      final groups = parseCampusPlaces(raw);
      for (final feature in parseCampusMapFeatures(raw)) {
        final key = '${feature['kind']}:${feature['id']}';
        if (seenMapFeatures.add(key)) mapFeatures.add(feature);
      }
      groups.forEach((subId, places) {
        if (places.isEmpty) return;
        byKind[placeKinds[subId]!.$1] = places;
      });
    } catch (_) {
      failures.add(parent);
    }
  }

  if (byKind.isEmpty) {
    throw UpstreamError('no campus places parsed, failed parents: $failures');
  }
  return {'kinds': byKind, 'map_features': mapFeatures};
}

// --- projections -------------------------------------------------------

/// The kinds that actually have places, in the declared order.
List<Map<String, dynamic>> placeKindSummary(Map<String, dynamic>? snapshot) {
  final kinds = snapshot?['kinds'] as Map<String, dynamic>? ?? const {};
  final out = <Map<String, dynamic>>[];

  for (final entry in placeKinds.values) {
    final places = kinds[entry.$1] as List<dynamic>?;
    if (places == null || places.isEmpty) continue;
    // kind_name, not name: PlaceKind.fromJson reads that key, and a mismatch
    // renders the sheet with blank labels rather than failing.
    out.add({'kind': entry.$1, 'kind_name': entry.$2, 'count': places.length});
  }
  return out;
}

List<Map<String, dynamic>> placesOfKind(
  Map<String, dynamic>? snapshot,
  String kind,
) {
  final kinds = snapshot?['kinds'] as Map<String, dynamic>? ?? const {};
  final places = <Map<String, dynamic>>[
    for (final p in kinds[kind] as List<dynamic>? ?? const [])
      p as Map<String, dynamic>,
  ];
  places.sort((a, b) {
    final byBuilding = '${a['building'] ?? ''}'.compareTo(
      '${b['building'] ?? ''}',
    );
    return byBuilding != 0
        ? byBuilding
        : '${a['name']}'.compareTo('${b['name']}');
  });
  return places;
}

List<Map<String, dynamic>> campusMapFeatures(Map<String, dynamic>? snapshot) {
  final features = <Map<String, dynamic>>[
    for (final feature
        in snapshot?['map_features'] as List<dynamic>? ?? const [])
      feature as Map<String, dynamic>,
  ];
  features.sort((a, b) {
    final byKind = '${a['kind']}'.compareTo('${b['kind']}');
    return byKind != 0 ? byKind : '${a['name']}'.compareTo('${b['name']}');
  });
  return features;
}
