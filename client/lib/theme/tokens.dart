/// Design tokens.
///
/// Shapes, radii, and type scale live here so they are reused rather than
/// re-derived at each call site.
library;

import 'package:flutter/material.dart';

class Shapes {
  const Shapes._();

  /// The signature scalloped "cookie" badge.
  ///
  /// Note on the values: StarBorder asserts that
  /// `pointRounding + valleyRounding <= 1`, so the 1.0/1.0 pair in the brief
  /// throws at construction. Splitting the budget evenly gives the fully
  /// lobed look while staying inside the assert.
  static const ShapeBorder badge = StarBorder(
    points: 8,
    innerRadiusRatio: 0.9,
    pointRounding: 0.5,
    valleyRounding: 0.5,
  );

  /// Cards. Nothing in the app is below 12, and no card is below 28.
  static const double cardRadius = 30;
  static const double innerRadius = 20;
  static const double smallRadius = 14;

  static final BorderRadius card = BorderRadius.circular(cardRadius);
  static final BorderRadius inner = BorderRadius.circular(innerRadius);
  static final BorderRadius small = BorderRadius.circular(smallRadius);

  /// Chips, buttons, the occupancy indicator.
  static const StadiumBorder pill = StadiumBorder();
}

class Insets {
  const Insets._();

  static const double cardPadding = 20;
  static const double gutter = 10;
}

/// Rubik is a variable font, so weights are chosen on the wght axis rather
/// than by loading separate faces.
class Weights {
  const Weights._();

  static const List<FontVariation> light = [FontVariation('wght', 300)];
  static const List<FontVariation> regular = [FontVariation('wght', 400)];
  static const List<FontVariation> medium = [FontVariation('wght', 500)];
  static const List<FontVariation> semibold = [FontVariation('wght', 600)];
}
