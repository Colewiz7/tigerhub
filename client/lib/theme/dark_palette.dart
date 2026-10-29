/// The built-in dark palettes.
///
/// Each is a fixed set of hex values laid over the seed scheme. Nothing here
/// reads the OS or the wallpaper. Contrast for every pair that matters is
/// asserted per palette in `test/dark_palette_test.dart`.
library;

import 'package:flutter/material.dart';

class DarkPalette {
  const DarkPalette({
    required this.id,
    required this.name,
    required this.bg,
    required this.surface,
    required this.elevated,
    required this.text,
    required this.muted,
    required this.accent,
    required this.success,
    required this.busy,
    this.closedTone = 59,
  });

  final String id;
  final String name;
  final Color bg, surface, elevated, text, muted, accent;

  /// Chip foregrounds, lifted until they hold 4.5:1 on their own tint.
  final Color success, busy;

  /// HCT tone of the closed terracotta, set per palette so it holds 4.5:1 on
  /// that palette's cards.
  final double closedTone;

  static const espresso = DarkPalette(
    id: 'espresso',
    name: 'Espresso',
    bg: Color(0xFF140A08),
    surface: Color(0xFF2A1E1A),
    elevated: Color(0xFF382A25),
    text: Color(0xFFF2E6DE),
    muted: Color(0xFFC6B3A8),
    accent: Color(0xFFF3B08F),
    success: Color(0xFF81AF7D),
    busy: Color(0xFFC7942F),
  );

  static const mocha = DarkPalette(
    id: 'mocha',
    name: 'Mocha',
    bg: Color(0xFF171311),
    surface: Color(0xFF2D2622),
    elevated: Color(0xFF3C342F),
    text: Color(0xFFF5EFEA),
    muted: Color(0xFFBFB2A8),
    accent: Color(0xFFD9B8A0),
    success: Color(0xFF9CB193),
    busy: Color(0xFFC3AB7D),
    closedTone: 63,
  );

  static const slate = DarkPalette(
    id: 'slate',
    name: 'Slate',
    bg: Color(0xFF151312),
    surface: Color(0xFF23201E),
    elevated: Color(0xFF312D2A),
    text: Color(0xFFF7F2EC),
    muted: Color(0xFFBEB4AB),
    accent: Color(0xFFE2C2A2),
    success: Color(0xFF91A58C),
    busy: Color(0xFFBDA379),
  );

  static const all = [espresso, mocha, slate];

  /// A chip fill: the chip colour at low alpha over a card. The tint is part
  /// of the pair, so the alpha is low enough that the pair still holds 4.5:1.
  Color chip(Color c, {double alpha = 0.16}) => Color.alphaBlend(c.withValues(alpha: alpha), surface);

  /// Lay the palette over a generated dark scheme. Roles the palette does not
  /// name keep their generated values.
  ColorScheme apply(ColorScheme base) => base.copyWith(
    surface: bg,
    surfaceContainerLowest: bg,
    surfaceContainerLow: surface,
    surfaceContainer: Color.alphaBlend(elevated.withValues(alpha: 0.5), surface),
    surfaceContainerHigh: elevated,
    surfaceContainerHighest: Color.alphaBlend(text.withValues(alpha: 0.06), elevated),
    onSurface: text,
    onSurfaceVariant: muted,
    primary: accent,
    onPrimary: bg,
  );

  /// The palette a scheme was built from, or null for any other scheme.
  static DarkPalette? of(ColorScheme scheme) {
    if (scheme.brightness != Brightness.dark) return null;
    for (final p in all) {
      if (scheme.primary == p.accent && scheme.surfaceContainerLowest == p.bg) return p;
    }
    return null;
  }
}
