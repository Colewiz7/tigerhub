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

  /// Reference hues before harmonizing. Chosen for recognisability, not for
  /// looking good next to any particular wallpaper, which is what harmonize
  /// then takes care of.
  static const Color _greenSeed = Color(0xFF2E7D32);
  static const Color _redSeed = Color(0xFFC62828);
  static const Color _amberSeed = Color(0xFFF9A825);

  static Color _harmonize(Color design, Color towards) =>
      Color(Blend.harmonize(design.toARGB32(), towards.toARGB32()));

  /// Build from whatever scheme is currently in force.
  factory Semantic.from(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;

    Color tone(Color seed, {required double lightness}) {
      final harmonized = _harmonize(seed, scheme.primary);
      final hct = Hct.fromInt(harmonized.toARGB32());
      hct.tone = lightness;
      return Color(hct.toInt());
    }

    // Foreground tones sit high in dark mode and low in light mode so text
    // stays legible either way.
    final fg = dark ? 78.0 : 40.0;
    final container = dark ? 26.0 : 90.0;
    final onContainer = dark ? 90.0 : 20.0;

    return Semantic(
      open: tone(_greenSeed, lightness: fg),
      onOpen: tone(_greenSeed, lightness: onContainer),
      openContainer: tone(_greenSeed, lightness: container),
      // Closed is muted rather than alarming. Nothing is wrong, it is just shut.
      closed: tone(_redSeed, lightness: dark ? 58.0 : 52.0),
      closedContainer: tone(_redSeed, lightness: dark ? 20.0 : 93.0),
      busy: tone(_amberSeed, lightness: fg),
      onBusy: tone(_amberSeed, lightness: onContainer),
      busyContainer: tone(_amberSeed, lightness: container),
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
