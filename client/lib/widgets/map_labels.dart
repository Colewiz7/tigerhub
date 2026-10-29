/// Label priorities, sizes and collision planning for the campus map.
///
/// Everything here is in screen points. The painter multiplies canvas
/// coordinates by the zoom before planning, so a label is the same size at
/// every zoom and only the room around it changes.
library;

import 'dart:ui';

/// Nothing on the map is set below this.
const double mapLabelMinSize = 11;

/// Category glyphs, the grayscale cue, show from this zoom upward.
const double mapGlyphMinZoom = 3;

/// Full names may sit just outside a small building from this zoom upward.
const double mapFullNameOutsideZoom = 8;

/// Space kept between any two accepted labels.
const double mapLabelPadding = 3;

/// In collision priority order: earlier wins.
enum LabelClass {
  selected(15, FontWeight.w600, 2.0),
  activePin(13, FontWeight.w600, 1.5),
  fullName(13, FontWeight.w500, 1.5),
  abbreviation(12, FontWeight.w600, 1.5),
  street(11.5, FontWeight.w400, 1.5),
  entrance(12, FontWeight.w500, 1.5);

  const LabelClass(this.size, this.weight, this.halo)
    : assert(size >= mapLabelMinSize);

  final double size;
  final FontWeight weight;

  /// Hard, non-blurred glyph outline in the ground colour.
  final double halo;
}

/// Whether the category glyph is drawn beside a building label at [zoom].
bool mapGlyphShown(LabelClass cls, double zoom) =>
    zoom >= mapGlyphMinZoom &&
    (cls == LabelClass.selected ||
        cls == LabelClass.fullName ||
        cls == LabelClass.abbreviation);

/// One thing that wants a label, with the places it may go in order.
class LabelCandidate {
  const LabelCandidate({
    required this.key,
    required this.cls,
    required this.size,
    required this.positions,
    this.group,
    this.weight = 0,
    this.payload,
    this.text = '',
    this.glyph = false,
  });

  final String text;

  /// Whether a category glyph is drawn before the text.
  final bool glyph;

  /// Whatever the painter needs to draw this label once it is placed.
  final Object? payload;

  final Object key;
  final LabelClass cls;

  /// Measured size on screen, glyph included.
  final Size size;

  /// Rectangles to try, best first.
  final List<Rect> positions;

  /// Candidates of one group are alternatives: once one is placed the rest
  /// are dropped, so a building shows its full name or its abbreviation.
  final Object? group;

  /// Tie-break inside a class, bigger first.
  final double weight;
}

class PlacedLabel {
  const PlacedLabel(this.candidate, this.rect);

  final LabelCandidate candidate;
  final Rect rect;
}

/// Greedy placement by class priority.
///
/// Each accepted rectangle is grown by [mapLabelPadding] on every side before
/// it is tested against later candidates. [obstacles] (pins) are fixed and
/// beat every label. A selected label is always kept, even when no position
/// is free, in its first position.
List<PlacedLabel> planLabels(
  List<LabelCandidate> candidates, {
  List<Rect> obstacles = const [],
}) {
  final ordered = [...candidates]
    ..sort((a, b) {
      final byClass = a.cls.index.compareTo(b.cls.index);
      return byClass != 0 ? byClass : b.weight.compareTo(a.weight);
    });
  final taken = <Rect>[...obstacles];
  final done = <Object>{};
  final out = <PlacedLabel>[];
  for (final candidate in ordered) {
    final group = candidate.group;
    if (group != null && done.contains(group)) continue;
    Rect? chosen;
    for (final position in candidate.positions) {
      final padded = position.inflate(mapLabelPadding);
      if (!taken.any(padded.overlaps)) {
        chosen = position;
        break;
      }
    }
    if (chosen == null && candidate.cls == LabelClass.selected) {
      chosen = candidate.positions.first;
    }
    if (chosen == null) continue;
    taken.add(chosen);
    if (group != null) done.add(group);
    out.add(PlacedLabel(candidate, chosen));
  }
  return out;
}

/// The positions for a building label of [size]: inside its [bounds] when it
/// fits, else centred under it when [outside] allows.
List<Rect> buildingPositions(Rect bounds, Size size, {required bool outside}) {
  final fits =
      size.width + 6 <= bounds.width && size.height + 4 <= bounds.height;
  return [
    if (fits) Rect.fromCenter(
      center: bounds.center,
      width: size.width,
      height: size.height,
    ),
    if (!fits && outside)
      Rect.fromCenter(
        center: Offset(bounds.center.dx, bounds.bottom + size.height / 2 + 3),
        width: size.width,
        height: size.height,
      ),
  ];
}
