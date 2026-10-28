/// Tints for the diet and protein classes on a menu.
///
/// Unlike the status colours these are not harmonized toward the wallpaper:
/// green has to stay green and red has to stay red for the code to be read at a
/// glance. Each class is a fixed hue and chroma at tones picked for contrast,
/// so text on it clears 4.5:1 in both modes whatever the scheme. The label that
/// goes with every tint is what carries the meaning for anyone who cannot tell
/// the hues apart.
library;

import 'package:flutter/material.dart';
// Comes in transitively with the Flutter SDK. See semantic.dart.
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

import '../models/diet_class.dart';

@immutable
class DietColors {
  const DietColors({
    required this.container,
    required this.onContainer,
    required this.accent,
    required this.onAccent,
  });

  /// The dish row.
  final Color container;
  final Color onContainer;

  /// The label chip.
  final Color accent;
  final Color onAccent;

  static DietColors lerp(DietColors a, DietColors b, double t) => DietColors(
    container: Color.lerp(a.container, b.container, t)!,
    onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
    accent: Color.lerp(a.accent, b.accent, t)!,
    onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
  );
}

@immutable
class DietPalette extends ThemeExtension<DietPalette> {
  const DietPalette(this._colors);

  final Map<DietClass, DietColors> _colors;

  DietColors operator [](DietClass kind) => _colors[kind]!;

  /// (hue, chroma, light container tone, dark container tone). Vegetarian is
  /// the paler, greyer green; pork the paler red; chicken is cream.
  static const _tints = <DietClass, (double, double, double, double)>{
    DietClass.vegan: (145, 50, 82, 24),
    DietClass.vegetarian: (125, 24, 93, 32),
    DietClass.beef: (28, 55, 83, 26),
    DietClass.pork: (350, 30, 90, 32),
    DietClass.chicken: (88, 18, 95, 34),
    DietClass.fish: (250, 38, 85, 26),
  };

  factory DietPalette.from(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;

    Color tone(double hue, double chroma, double tone) =>
        Color(Hct.from(hue, chroma, tone).toInt());

    return DietPalette({
      for (final entry in _tints.entries)
        entry.key: DietColors(
          container: tone(entry.value.$1, entry.value.$2, dark ? entry.value.$4 : entry.value.$3),
          onContainer: tone(entry.value.$1, 8, dark ? 92 : 10),
          accent: tone(entry.value.$1, entry.value.$2 + 12, dark ? 78 : 38),
          onAccent: tone(entry.value.$1, 8, dark ? 10 : 100),
        ),
      DietClass.other: DietColors(
        container: scheme.surfaceContainerHigh,
        onContainer: scheme.onSurface,
        accent: scheme.surfaceContainerHighest,
        onAccent: scheme.onSurface,
      ),
    });
  }

  static DietPalette of(BuildContext context) =>
      Theme.of(context).extension<DietPalette>() ??
      DietPalette.from(Theme.of(context).colorScheme);

  @override
  DietPalette copyWith() => DietPalette(_colors);

  @override
  DietPalette lerp(ThemeExtension<DietPalette>? other, double t) {
    if (other is! DietPalette) return this;
    return DietPalette({
      for (final kind in DietClass.values)
        kind: DietColors.lerp(this[kind], other[kind], t),
    });
  }
}
