/// Geometry helpers for the bundled OpenStreetMap layers.
///
/// Pure functions on projected points, so they test without a canvas.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../models/api_models.dart';

/// Ground distance between two coordinates in metres, flat-earth, which is
/// exact enough over a campus.
double metresApart(GeoCoordinate a, GeoCoordinate b) {
  const metresPerDegree = 111320.0;
  final dy = (a.latitude - b.latitude) * metresPerDegree;
  final dx =
      (a.longitude - b.longitude) *
      metresPerDegree *
      math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

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

/// Even-odd point in ring test.
bool pointInRing(Offset p, List<Offset> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// The average of the vertices. Enough to place a point inside a footprint.
Offset ringCentre(List<Offset> ring) {
  var sum = Offset.zero;
  for (final p in ring) {
    sum += p;
  }
  return sum / ring.length.toDouble();
}

Rect _boundsOf(List<Offset> ring) {
  var left = ring.first.dx, right = left;
  var top = ring.first.dy, bottom = top;
  for (final p in ring) {
    if (p.dx < left) left = p.dx;
    if (p.dx > right) right = p.dx;
    if (p.dy < top) top = p.dy;
    if (p.dy > bottom) bottom = p.dy;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

double _cross(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

/// Proper crossing only. Segments that merely touch or run along each other
/// are a shared wall, not an overlap.
bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  final d1 = _cross(a, b, c), d2 = _cross(a, b, d);
  final d3 = _cross(c, d, a), d4 = _cross(c, d, b);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Whether two rings share any area: an edge crosses, or one sits inside the
/// other. The bounds are checked first, so most pairs cost four comparisons.
bool ringsOverlap(List<Offset> a, List<Offset> b) {
  if (!_boundsOf(a).overlaps(_boundsOf(b))) return false;
  for (var i = 0; i < a.length; i++) {
    final a0 = a[i], a1 = a[(i + 1) % a.length];
    for (var j = 0; j < b.length; j++) {
      if (_segmentsCross(a0, a1, b[j], b[(j + 1) % b.length])) return true;
    }
  }
  return pointInRing(ringCentre(a), b) ||
      pointInRing(ringCentre(b), a) ||
      pointInRing(a.first, b) ||
      pointInRing(b.first, a);
}

/// The [candidates] that share no area with any of [authoritative].
///
/// RIT's footprints are authoritative, so an OpenStreetMap outline for a
/// building RIT already draws is dropped whole rather than drawn twice.
List<List<Offset>> outsideRings(
  Iterable<List<Offset>> candidates,
  List<List<Offset>> authoritative,
) => [
  for (final ring in candidates)
    if (ring.length >= 3 && !authoritative.any((r) => ringsOverlap(ring, r)))
      ring,
];

/// One path of open lines.
Path linesPath(Iterable<List<Offset>> lines) {
  final path = Path();
  for (final line in lines) {
    if (line.length < 2) continue;
    path.addPolygon(line, false);
  }
  return path;
}
