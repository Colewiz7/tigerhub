/// Conservative event placement for the offline campus map.
///
/// An event is placed through the reviewed alias table first. A string the
/// table never ruled on falls back to an exact building abbreviation already
/// present in map data. There is intentionally no fuzzy fallback and no pin at
/// campus centre.
library;

import '../data/campus_time.dart';
import '../data/event_aliases.dart';
import '../data/sources/athletics.dart';
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
  // [day] is a campus calendar date; the window is that campus day.
  final target = day ?? CampusTime.wallDate();
  final start = CampusTime.wall(target.year, target.month, target.day);
  final end = CampusTime.wall(target.year, target.month, target.day + 1);
  final today = events
      .where(
        (event) =>
            !event.startsAt.isBefore(start) && event.startsAt.isBefore(end),
      )
      .toList(growable: false);

  final anchors = <String, GeoCoordinate>{};
  final byBuilding = <String, List<CampusMapFeature>>{};
  for (final feature in features) {
    final building = feature.building?.trim().toUpperCase();
    if (building == null || building.length < 2 || feature.anchor == null) {
      continue;
    }
    byBuilding.putIfAbsent(building, () => []).add(feature);
  }
  byBuilding.forEach((building, members) {
    final points = [for (final m in members) m.anchor!];
    final average = GeoCoordinate(
      points.fold<double>(0, (sum, point) => sum + point.longitude) /
          points.length,
      points.fold<double>(0, (sum, point) => sum + point.latitude) /
          points.length,
    );
    // no outline means the average can land off the building, so use the
    // real amenity point nearest to it
    final outlined = members.any((m) => m.geometryType != 'Point');
    anchors[building] = outlined
        ? average
        : points.reduce(
            (a, b) => _distance(a, average) <= _distance(b, average) ? a : b,
          );
  });

  final named = <String, GeoCoordinate>{};
  for (final feature in features) {
    final anchor = feature.anchor;
    if (anchor == null) continue;
    named.putIfAbsent(feature.name.trim().toUpperCase(), () => anchor);
  }

  final matched = <String, List<CampusEvent>>{};
  final labels = <String, String>{};
  final spots = <String, GeoCoordinate>{};
  var unmapped = 0;
  for (final event in today) {
    final location = event.location;
    if (location == null || location.trim().isEmpty) {
      unmapped++;
      continue;
    }

    final athletics = event.source == athleticsSource;
    final pin = matchEventAlias(
      location: location,
      building: event.building,
      athletics: athletics,
    );
    String? key;
    if (pin != null) {
      final code = pin.code?.toUpperCase();
      final name = pin.featureName?.trim().toUpperCase();
      if (code != null && anchors.containsKey(code)) {
        key = code;
        spots[key] = anchors[code]!;
        labels[key] = code;
      } else if (code == null && name != null && named.containsKey(name)) {
        // an outdoor spot pins to its own feature, never to a building
        key = 'F:$name';
        spots[key] = named[name]!;
        labels[key] = pin.featureName!;
      }
    } else if (!eventAliasDecided(
      location: location,
      building: event.building,
      athletics: athletics,
    )) {
      final text = location.toUpperCase();
      final matches = anchors.keys.where((building) {
        final escaped = RegExp.escape(building);
        return RegExp('(^|[^A-Z0-9])$escaped([^A-Z0-9]|\$)').hasMatch(text);
      }).toList();
      if (matches.length == 1) {
        key = matches.single;
        spots[key] = anchors[key]!;
        labels[key] = key;
      }
    }
    if (key == null) {
      // Zero is unknown. More than one is ambiguous. Neither may pin.
      unmapped++;
      continue;
    }
    matched.putIfAbsent(key, () => []).add(event);
  }

  var id = -1;
  final groups = <MappedEventGroup>[
    for (final entry in matched.entries)
      MappedEventGroup(
        id: id--,
        building: labels[entry.key]!,
        coordinate: spots[entry.key]!,
        events: entry.value..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
      ),
  ]..sort((a, b) => a.events.first.startsAt.compareTo(b.events.first.startsAt));

  return CampusEventMapResult(groups: groups, unmapped: unmapped);
}

double _distance(GeoCoordinate a, GeoCoordinate b) {
  final dx = a.longitude - b.longitude;
  final dy = a.latitude - b.latitude;
  return dx * dx + dy * dy;
}
