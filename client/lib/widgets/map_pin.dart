/// The scalloped map pin: seven lobes, each a real circular arc.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Fixed on purpose. 8 and 10 lobes read as noise at 22 pt.
const int scallopLobes = 7;

// notch distance from the centre, as a share of the lobe peak distance
const double _notchRatio = 0.93;

/// One lobe: the circle it is cut from and the span of it that is drawn.
typedef ScallopArc = ({
  Offset center,
  double radius,
  Offset from,
  Offset to,
});

/// The seven arcs of a pin whose lobe peaks sit [radius] from [center], with
/// the first peak straight up.
///
/// Each arc runs between two neighbouring notches and bulges outward, so the
/// outline is seven arcs meeting at seven corners and nothing else.
List<ScallopArc> scallopArcs(Offset center, double radius) {
  final step = 2 * math.pi / scallopLobes;
  final notch = radius * _notchRatio;
  Offset notchAt(int index) {
    final angle = -math.pi / 2 + (index + 0.5) * step;
    return center + Offset(math.cos(angle), math.sin(angle)) * notch;
  }

  // The lobe circle passes through both notches and the peak between them.
  final halfChord = notch * math.sin(step / 2);
  final sagitta = radius - notch * math.cos(step / 2);
  final lobeRadius = (halfChord * halfChord + sagitta * sagitta) / (2 * sagitta);
  return [
    for (var i = 0; i < scallopLobes; i++)
      (
        // the peak of lobe i is at angle i * step from straight up
        center:
            center +
            Offset(
                  math.cos(-math.pi / 2 + i * step),
                  math.sin(-math.pi / 2 + i * step),
                ) *
                (radius - lobeRadius),
        radius: lobeRadius,
        from: notchAt(i - 1),
        to: notchAt(i),
      ),
  ];
}

/// The closed outline for [scallopArcs], built with arc segments.
Path scallopPath(Offset center, double radius) {
  final arcs = scallopArcs(center, radius);
  final path = Path()..moveTo(arcs.first.from.dx, arcs.first.from.dy);
  for (final arc in arcs) {
    path.arcToPoint(
      arc.to,
      radius: Radius.circular(arc.radius),
      clockwise: true,
    );
  }
  return path..close();
}
