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

    Color tone(
      Color seed, {
      required double lightness,
      required double chromaScale,
    }) {
      final harmonized = _harmonize(seed, scheme.primary);
      final hct = Hct.fromInt(harmonized.toARGB32());
      hct.tone = lightness;
      hct.chroma *= chromaScale;
      return Color(hct.toInt());
    }

    // Pull all three status families toward the row surface and shed more than
    // half their chroma. They remain legible state cues, while the primary
    // keeps the strongest color contrast on the screen.
    final surfaceTone =
        Hct.fromInt(scheme.surfaceContainerHigh.toARGB32()).tone;
    final fg = dark ? surfaceTone + 42.0 : surfaceTone - 42.0;
    final container = dark ? surfaceTone + 5.0 : surfaceTone - 5.0;
    final onContainer = dark ? surfaceTone + 58.0 : surfaceTone - 58.0;
    const foregroundChroma = 0.45;
    const containerChroma = 0.22;

    return Semantic(
      open: tone(
        _greenSeed,
        lightness: fg,
        chromaScale: foregroundChroma,
      ),
      onOpen: tone(
        _greenSeed,
        lightness: onContainer,
        chromaScale: foregroundChroma,
      ),
      openContainer: tone(
        _greenSeed,
        lightness: container,
        chromaScale: containerChroma,
      ),
      // Closed is muted rather than alarming. Nothing is wrong, it is just shut.
      closed: tone(
        _redSeed,
        lightness: fg,
        chromaScale: foregroundChroma,
      ),
      closedContainer: tone(
        _redSeed,
        lightness: container,
        chromaScale: containerChroma,
      ),
      busy: tone(
        _amberSeed,
        lightness: fg,
        chromaScale: foregroundChroma,
      ),
      onBusy: tone(
        _amberSeed,
        lightness: onContainer,
        chromaScale: foregroundChroma,
      ),
      busyContainer: tone(
        _amberSeed,
        lightness: container,
        chromaScale: containerChroma,
      ),
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
