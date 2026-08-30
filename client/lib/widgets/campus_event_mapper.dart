/// Conservative event placement for the offline campus map.
///
/// An event is placed only when its location contains an exact building
/// abbreviation already present in map data. There is intentionally no fuzzy
/// fallback and no pin at campus centre.
library;

import '../models/api_models.dart';

class MappedEventGroup {
  const MappedEventGroup({
    required this.id,
    required this.building,
    required this.coordinate,
    required this.events,
  });

  final int id;
  final String building;
  final GeoCoordinate coordinate;
  final List<CampusEvent> events;

  CampusMapFeature get mapFeature => CampusMapFeature(
    id: id,
    kind: '_event:${events.length}',
    kindName: 'Events',
    name: events.length == 1
        ? events.single.title
        : '${events.length} events at $building',
    geometryType: 'Point',
    coordinates: [
      [coordinate],
    ],
    building: building,
  );
}

class CampusEventMapResult {
  const CampusEventMapResult({required this.groups, required this.unmapped});

  final List<MappedEventGroup> groups;
  final int unmapped;

  int get mapped =>
      groups.fold(0, (count, group) => count + group.events.length);
}

CampusEventMapResult mapCampusEvents(
  List<CampusEvent> events,
  List<CampusMapFeature> features, {
  DateTime? day,
}) {
  final target = day ?? DateTime.now();
  final start = DateTime(target.year, target.month, target.day);
  final end = start.add(const Duration(days: 1));
  final today = events
      .where(
        (event) =>
            !event.startsAt.isBefore(start) && event.startsAt.isBefore(end),
      )
      .toList(growable: false);

  final anchors = <String, GeoCoordinate>{};
  final byBuilding = <String, List<GeoCoordinate>>{};
  for (final feature in features) {
    final building = feature.building?.trim().toUpperCase();
    final anchor = feature.anchor;
    if (building == null || building.length < 2 || anchor == null) continue;
    byBuilding.putIfAbsent(building, () => []).add(anchor);
  }
  byBuilding.forEach((building, points) {
    anchors[building] = GeoCoordinate(
      points.fold<double>(0, (sum, point) => sum + point.longitude) /
          points.length,
      points.fold<double>(0, (sum, point) => sum + point.latitude) /
          points.length,
    );
  });

  final matched = <String, List<CampusEvent>>{};
  var unmapped = 0;
  for (final event in today) {
    final location = event.location?.toUpperCase();
    if (location == null || location.trim().isEmpty) {
      unmapped++;
      continue;
    }

    final matches = anchors.keys.where((building) {
      final escaped = RegExp.escape(building);
      return RegExp('(^|[^A-Z0-9])$escaped([^A-Z0-9]|\$)').hasMatch(location);
    }).toList();
    if (matches.length != 1) {
      // Zero is unknown. More than one is ambiguous. Neither may pin.
      unmapped++;
      continue;
    }
    matched.putIfAbsent(matches.single, () => []).add(event);
  }

  var id = -1;
  final groups = <MappedEventGroup>[
    for (final entry in matched.entries)
      MappedEventGroup(
        id: id--,
        building: entry.key,
        coordinate: anchors[entry.key]!,
        events: entry.value..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
      ),
  ]..sort((a, b) => a.events.first.startsAt.compareTo(b.events.first.startsAt));

  return CampusEventMapResult(groups: groups, unmapped: unmapped);
}
