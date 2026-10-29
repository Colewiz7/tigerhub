/// Geometry helpers for the bundled OpenStreetMap layers.
///
/// Pure functions on projected points, so they test without a canvas.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter;

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

/// A stretch of a street that stays close to one heading.
typedef StraightRun = ({
  List<Offset> points,
  double length,
  Offset mid,
});

/// The point [fraction] of the way along [points] by arc length.
Offset pointAlong(List<Offset> points, double fraction) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += (points[i] - points[i - 1]).distance;
  }
  var left = total * fraction;
  for (var i = 1; i < points.length; i++) {
    final step = (points[i] - points[i - 1]).distance;
    if (left <= step && step > 0) {
      return Offset.lerp(points[i - 1], points[i], left / step)!;
    }
    left -= step;
  }
  return points.last;
}

double _heading(Offset v) => math.atan2(v.dy, v.dx);

double _turn(double a, double b) {
  var d = (a - b).abs() % (2 * math.pi);
  if (d > math.pi) d = 2 * math.pi - d;
  return d;
}

/// The longest run in [lines] whose every segment stays within [maxTurn]
/// radians of the run's overall heading, or null when there are none.
///
/// A street is split at its bends. The longest straight stretch is the part
/// of the street a label can sit on without the text leaving the road.
StraightRun? longestStraightRun(
  List<List<Offset>> lines, {
  double maxTurn = 0.35,
}) {
  StraightRun? best;
  for (final line in lines) {
    var start = 0;
    while (start < line.length - 1) {
      var end = start + 1;
      while (end < line.length - 1) {
        final chord = _heading(line[end + 1] - line[start]);
        var straight = true;
        for (var i = start; i <= end; i++) {
          if (_turn(_heading(line[i + 1] - line[i]), chord) > maxTurn) {
            straight = false;
            break;
          }
        }
        if (!straight) break;
        end++;
      }
      final points = line.sublist(start, end + 1);
      var length = 0.0;
      for (var i = 1; i < points.length; i++) {
        length += (points[i] - points[i - 1]).distance;
      }
      if (best == null || length > best.length) {
        best = (points: points, length: length, mid: pointAlong(points, .5));
      }
      start = end;
    }
  }
  return best;
}

/// The longest run in [lines] that bends gently enough to set text along.
///
/// No single bend may exceed [maxBend] radians and the run may turn by no more
/// than [maxTotal] radians in all, about 57 degrees. A hairpin or an S is left
/// for the upright label.
StraightRun? longestGentleRun(
  List<List<Offset>> lines, {
  double maxBend = 0.5,
  double maxTotal = 1.0,
}) {
  StraightRun? best;
  for (final line in lines) {
    var start = 0;
    while (start < line.length - 1) {
      var end = start + 1;
      var total = 0.0;
      while (end < line.length - 1) {
        final bend = _turn(
          _heading(line[end + 1] - line[end]),
          _heading(line[end] - line[end - 1]),
        );
        if (bend > maxBend || total + bend > maxTotal) break;
        total += bend;
        end++;
      }
      final points = line.sublist(start, end + 1);
      var length = 0.0;
      for (var i = 1; i < points.length; i++) {
        length += (points[i] - points[i - 1]).distance;
      }
      if (best == null || length > best.length) {
        best = (points: points, length: length, mid: pointAlong(points, .5));
      }
      start = end;
    }
  }
  return best;
}

/// One glyph set on a path: which character, where its centre goes, and the
/// angle to turn it by so its baseline follows the path.
typedef PathGlyph = ({int index, Offset at, double angle});

/// A street name laid out glyph by glyph along its run.
class PathLabel {
  const PathLabel(this.glyphs, this.inks);

  final List<PathGlyph> glyphs;

  /// The fill and halo of each character, in the order of [glyphs].
  final List<({TextPainter fill, TextPainter halo})> inks;
}

/// Sets glyphs of the given [advances] along [points], centred on the run.
///
/// Reads left to right: a run that heads leftward is walked backward, so no
/// glyph is ever upside down. Returns null when the text is longer than the
/// run, so a label can never spill off its street, or when the path turns so
/// hard that a glyph would stand on its head anyway.
List<PathGlyph>? layoutAlongRun(List<Offset> points, List<double> advances) {
  if (points.length < 2 || advances.isEmpty) return null;
  final chord = _heading(points.last - points.first);
  final ordered = chord.abs() > math.pi / 2 ? points.reversed.toList() : points;
  final metric = (Path()..addPolygon(ordered, false)).computeMetrics().first;
  final width = advances.fold<double>(0, (a, b) => a + b);
  if (width > metric.length) return null;
  var distance = (metric.length - width) / 2;
  final out = <PathGlyph>[];
  for (var i = 0; i < advances.length; i++) {
    final tangent = metric.getTangentForOffset(distance + advances[i] / 2)!;
    final angle = _heading(tangent.vector);
    if (angle.abs() > 1.75) return null;
    out.add((index: i, at: tangent.position, angle: angle));
    distance += advances[i];
  }
  return out;
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
