/// Fixed campus map palette and zoom opacity schedules.
library;

import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

enum MapCategory { academic, residential, athletic, dining, other }

// fixed hex, never derived from the wallpaper theme
class MapPalette {
  const MapPalette({
    required this.ground,
    required this.grass,
    required this.water,
    required this.waterOutline,
    required this.academic,
    required this.residential,
    required this.athletic,
    required this.dining,
    required this.other,
    required this.buildingOutline,
    required this.parking,
    required this.parkingStroke,
    required this.roadCore,
    required this.roadCasing,
    required this.footpath,
    required this.entrance,
    required this.entranceOutline,
    required this.selectedOverlay,
    required this.selectedOutline,
    required this.labelInk,
    required this.labelSecondary,
    required this.labelHalo,
    required this.clusterBadge,
    required this.clusterBadgeText,
    required this.pinPlace,
    required this.onPinPlace,
    required this.pinUtility,
    required this.onPinUtility,
    required this.pinSafety,
    required this.onPinSafety,
    required this.chrome,
    required this.chromeInk,
    required this.chromeMuted,
    required this.chromeAccent,
    required this.chromeEdge,
  });

  final Color ground;
  final Color grass;
  final Color water;
  final Color waterOutline;
  final Color academic;
  final Color residential;
  final Color athletic;
  final Color dining;
  final Color other;
  final Color buildingOutline;
  final Color parking;
  final Color parkingStroke;
  final Color roadCore;
  final Color roadCasing;
  final Color footpath;
  final Color entrance;
  final Color entranceOutline;
  final Color selectedOverlay;
  final Color selectedOutline;
  final Color labelInk;
  final Color labelSecondary;
  final Color labelHalo;
  final Color clusterBadge;
  final Color clusterBadgeText;

  // pins: a place, a utility (water, transit), a safety point
  final Color pinPlace, onPinPlace;
  final Color pinUtility, onPinUtility;
  final Color pinSafety, onPinSafety;

  // controls and legend drawn over the map
  final Color chrome, chromeInk, chromeMuted, chromeAccent, chromeEdge;

  Color fill(MapCategory category) => switch (category) {
    MapCategory.academic => academic,
    MapCategory.residential => residential,
    MapCategory.athletic => athletic,
    MapCategory.dining => dining,
    MapCategory.other => other,
  };

  static MapPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const light = MapPalette(
    ground: Color(0xFFF7F5F2),
    grass: Color(0xFFE8F1E5),
    water: Color(0xFFDDEEF5),
    waterOutline: Color(0xFFBCD8E4),
    academic: Color(0xFFF5E1D2),
    residential: Color(0xFFECE8F5),
    athletic: Color(0xFFE2EFE4),
    dining: Color(0xFFF6E8D0),
    other: Color(0xFFE9E9E7),
    buildingOutline: Color(0xFFCFC6BD),
    parking: Color(0xFFEEEAE5),
    parkingStroke: Color(0xFFD7D1C9),
    // research had D7D3CD, 1.37 on ground, under the 1.5 floor
    roadCore: Color(0xFFCDC9C3),
    roadCasing: Color(0xFFFFFFFF),
    footpath: Color(0xFFAAA49C),
    entrance: Color(0xFFC75300),
    entranceOutline: Color(0xFFFFFFFF),
    selectedOverlay: Color(0x2EF76902),
    selectedOutline: Color(0xFFB54600),
    labelInk: Color(0xFF2C2B29),
    labelSecondary: Color(0xFF605D58),
    labelHalo: Color(0xFFF7F5F2),
    clusterBadge: Color(0xFFC75300),
    clusterBadgeText: Color(0xFFFFFFFF),
    pinPlace: Color(0xFFFFDBCC),
    onPinPlace: Color(0xFF703717),
    pinUtility: Color(0xFFFFDBCC),
    onPinUtility: Color(0xFF5C4033),
    pinSafety: Color(0xFFEDE4A9),
    onPinSafety: Color(0xFF4D481C),
    chrome: Color(0xFFFFF8F6),
    chromeInk: Color(0xFF221A16),
    chromeMuted: Color(0xFF52443D),
    chromeAccent: Color(0xFF8D4E2C),
    chromeEdge: Color(0xFFD7C2B9),
  );

  static const dark = MapPalette(
    ground: Color(0xFF151412),
    grass: Color(0xFF19231A),
    water: Color(0xFF14242B),
    waterOutline: Color(0xFF24414D),
    academic: Color(0xFF33251D),
    residential: Color(0xFF292631),
    athletic: Color(0xFF1E2B21),
    dining: Color(0xFF30281B),
    other: Color(0xFF242321),
    buildingOutline: Color(0xFF4B453F),
    parking: Color(0xFF1E1C1A),
    parkingStroke: Color(0xFF383532),
    roadCore: Color(0xFF3A3733),
    roadCasing: Color(0xFF24221F),
    footpath: Color(0xFF77716A),
    entrance: Color(0xFFFF9A4C),
    entranceOutline: Color(0xFF151412),
    selectedOverlay: Color(0x38F76902),
    selectedOutline: Color(0xFFFF9A4C),
    labelInk: Color(0xFFF2F0EC),
    labelSecondary: Color(0xFFC7C2BB),
    labelHalo: Color(0xFF151412),
    clusterBadge: Color(0xFFFF9A4C),
    clusterBadgeText: Color(0xFF151412),
    pinPlace: Color(0xFF703717),
    onPinPlace: Color(0xFFFFDBCC),
    pinUtility: Color(0xFF5C4033),
    onPinUtility: Color(0xFFFFDBCC),
    pinSafety: Color(0xFF4D481C),
    onPinSafety: Color(0xFFEDE4A9),
    chrome: Color(0xFF1A120E),
    chromeInk: Color(0xFFF0DFD8),
    chromeMuted: Color(0xFFD7C2B9),
    chromeAccent: Color(0xFFFFB693),
    chromeEdge: Color(0xFF52443D),
  );
}

const mapZoomStops = [1.0, 3.0, 8.0, 20.0];

// opacity per layer at mapZoomStops
class MapSchedule {
  static const ground = [1.0, 1.0, 1.0, 1.0];
  static const grass = [0.55, 0.75, 1.0, 1.0];
  static const water = [0.70, 0.85, 1.0, 1.0];
  static const building = [0.80, 1.0, 1.0, 1.0];
  static const otherBuilding = [0.75, 1.0, 1.0, 1.0];
  static const parking = [0.0, 0.45, 0.80, 1.0];
  static const roads = [0.45, 0.70, 1.0, 1.0];
  static const footpaths = [0.0, 0.45, 1.0, 1.0];
  static const entrances = [0.0, 0.0, 1.0, 1.0];
  static const selected = [1.0, 1.0, 1.0, 1.0];

  // the legend swatches show every layer fully on
  static const legendZoom = 20.0;
}

double opacityAt(List<double> anchors, double zoom) {
  assert(anchors.length == mapZoomStops.length);
  if (zoom <= mapZoomStops.first) return anchors.first;
  if (zoom >= mapZoomStops.last) return anchors.last;
  var i = 0;
  while (zoom > mapZoomStops[i + 1]) {
    i++;
  }
  final lo = mapZoomStops[i];
  final hi = mapZoomStops[i + 1];
  final t = math.log(zoom / lo) / math.log(hi / lo);
  return anchors[i] + (anchors[i + 1] - anchors[i]) * t;
}
