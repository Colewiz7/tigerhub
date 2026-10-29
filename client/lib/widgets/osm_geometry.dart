/// Geometry helpers for the bundled OpenStreetMap layers.
///
/// Pure functions on projected points, so they test without a canvas.
library;

import 'dart:ui';

/// Signed area of a ring. Positive when the points run clockwise on screen,
/// where y grows downward.
double signedArea(List<Offset> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}

/// One path of closed rings that all wind the same way.
///
/// Overlapping rings in a single path fill once under the default nonzero
/// rule, but two that wind opposite ways cancel and leave a hole. OSM does not
/// promise a winding, so every ring is turned the same way here. Separate
/// translucent fills would blend twice where they overlap.
Path ringsPath(Iterable<List<Offset>> rings) {
  final path = Path();
  for (final ring in rings) {
    if (ring.length < 3) continue;
    final ordered = signedArea(ring) < 0 ? ring.reversed.toList() : ring;
    path.addPolygon(ordered, true);
  }
  return path;
}

/// One path of open lines.
Path linesPath(Iterable<List<Offset>> lines) {
  final path = Path();
  for (final line in lines) {
    if (line.length < 2) continue;
    path.addPolygon(line, false);
  }
  return path;
}
