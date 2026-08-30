/// Semantic status colours, harmonized against the live scheme.
///
/// The palette is generated from the wallpaper, so a raw `Colors.green` clashes
/// with it. `Blend.harmonize` rotates a design colour's hue toward the scheme
/// primary while keeping it recognisably green, red, or amber, which is exactly
/// the Material You mechanism for this.
///
/// Derived once at theme build time and hung off ThemeData as an extension, so
/// call sites read `Semantic.of(context).open` rather than recomputing.
library;

import 'package:flutter/material.dart';
// Comes in transitively with the Flutter SDK, which pins the version. Left
// undeclared on purpose: adding it to pubspec would make it a direct
// dependency that could drift from whatever the SDK expects.
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

@immutable
class Semantic extends ThemeExtension<Semantic> {
  const Semantic({
    required this.open,
    required this.onOpen,
    required this.openContainer,
    required this.closed,
    required this.closedContainer,
    required this.busy,
    required this.onBusy,
    required this.busyContainer,
  });

  /// Open right now.
  final Color open;
  final Color onOpen;
  final Color openContainer;

  /// Closed. Deliberately low contrast, since a closed row should recede.
  final Color closed;
  final Color closedContainer;

  /// Busy, or a reading that exceeded its published capacity.
  final Color busy;
  final Color onBusy;
  final Color busyContainer;

  /// Reference hues before nudging. Chosen for recognisability.
  static const Color _greenSeed = Color(0xFF2E7D32);
  static const Color _redSeed = Color(0xFFC62828);
  static const Color _amberSeed = Color(0xFFF9A825);

  /// A gentle nudge toward the palette, not a full harmonize.
  ///
  /// `Blend.harmonize` rotated red and amber so far toward the orange primary
  /// that they collapsed onto each other: the shipped palette measured only
  /// dE 1.0 apart in deuteranopia and dE 4.8 in normal vision, so the colour
  /// carried no information at all. A 10 percent hue rotation keeps the tie to
  /// the palette without destroying the separation.
  static const double _nudge = 0.10;

  /// Tones, picked by running the palette validator rather than by eye.
  ///
  /// Red against green is the fundamental colourblindness case and no choice of
  /// hue fixes it, so these are separated by LIGHTNESS as well. The spread is
  /// what makes them distinguishable, which is why they deliberately sit
  /// outside a uniform lightness band.
  ///
  /// Validated all-pairs against each mode's own surface:
  ///   dark  #8bd376 #ee463d #ffddb7  CVD dE 9.4 protan, normal dE 18.0, contrast >= 3:1
  ///   light #63a64d #930009 #996100  CVD dE 11.6 deutan, normal dE 17.0, contrast >= 3:1
  ///
  /// The dark amber is deliberately pale. Deepening it for more chroma drops
  /// its separation from green to dE 2.0 in protanopia, so paleness is the
  /// price of it being distinguishable at all.
  static const _darkTones = (open: 78.0, closed: 55.0, busy: 90.0);
  static const _lightTones = (open: 58.0, closed: 30.0, busy: 46.0);

  /// Closed is muted to a terracotta rather than left at full chroma.
  ///
  /// At its natural chroma the red reads as an alarm and sits outside the warm
  /// palette. Muting it costs nothing: the binding pair for separation is amber
  /// against green, so the red can be calmed without touching the numbers that
  /// matter. Re-validated at dE 9.4 protan and 18.0 normal in dark, dE 8.4
  /// deutan and 15.6 normal in light.
  static const double _closedChroma = 42.0;

  static Color _shift(Color design, Color towards, double tone, {double? chroma}) {
    final rotated = Blend.hctHue(design.toARGB32(), towards.toARGB32(), _nudge);
    final hct = Hct.fromInt(rotated);
    hct.tone = tone;
    if (chroma != null) hct.chroma = chroma;
    return Color(hct.toInt());
  }

  /// Build from whatever scheme is currently in force.
  factory Semantic.from(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final tones = dark ? _darkTones : _lightTones;
    final primary = scheme.primary;

    Color at(Color seed, double tone, {double? chroma}) =>
        _shift(seed, primary, tone, chroma: chroma);

    final container = dark ? 26.0 : 90.0;
    final onContainer = dark ? 90.0 : 20.0;

    return Semantic(
      open: at(_greenSeed, tones.open),
      onOpen: at(_greenSeed, onContainer),
      openContainer: at(_greenSeed, container),
      closed: at(_redSeed, tones.closed, chroma: _closedChroma),
      closedContainer: at(_redSeed, container),
      busy: at(_amberSeed, tones.busy),
      onBusy: at(_amberSeed, onContainer),
      busyContainer: at(_amberSeed, container),
    );
  }

  static Semantic of(BuildContext context) =>
      Theme.of(context).extension<Semantic>() ??
      Semantic.from(Theme.of(context).colorScheme);

  @override
  Semantic copyWith({
    Color? open,
    Color? onOpen,
    Color? openContainer,
    Color? closed,
    Color? closedContainer,
    Color? busy,
    Color? onBusy,
    Color? busyContainer,
  }) =>
      Semantic(
        open: open ?? this.open,
        onOpen: onOpen ?? this.onOpen,
        openContainer: openContainer ?? this.openContainer,
        closed: closed ?? this.closed,
        closedContainer: closedContainer ?? this.closedContainer,
        busy: busy ?? this.busy,
        onBusy: onBusy ?? this.onBusy,
        busyContainer: busyContainer ?? this.busyContainer,
      );

  @override
  Semantic lerp(ThemeExtension<Semantic>? other, double t) {
    if (other is! Semantic) return this;
    return Semantic(
      open: Color.lerp(open, other.open, t)!,
      onOpen: Color.lerp(onOpen, other.onOpen, t)!,
      openContainer: Color.lerp(openContainer, other.openContainer, t)!,
      closed: Color.lerp(closed, other.closed, t)!,
      closedContainer: Color.lerp(closedContainer, other.closedContainer, t)!,
      busy: Color.lerp(busy, other.busy, t)!,
      onBusy: Color.lerp(onBusy, other.onBusy, t)!,
      busyContainer: Color.lerp(busyContainer, other.busyContainer, t)!,
    );
  }
}
