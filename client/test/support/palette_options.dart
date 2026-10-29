/// Dark palette candidates for the side-by-side comparison. Test only.
///
/// A palette is applied by overriding the dark ColorScheme, so every screen
/// keeps its real widgets and only the colours move. The roles map as:
///
///   Bg       scaffold, surface, surfaceContainerLowest
///   Surface  cards (surfaceContainerLow) and the glass tab bar tint
///   Elevated rows and fields (surfaceContainerHigh)
///   Text     onSurface
///   Muted    onSurfaceVariant
///   Accent   primary
///   Success  Semantic.open
///   Busy     Semantic.busy
library;

import 'package:flutter/material.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/theme/semantic.dart';

class PaletteOption {
  const PaletteOption(this.name, {
    required this.bg,
    required this.surface,
    required this.elevated,
    required this.text,
    required this.muted,
    required this.accent,
    required this.success,
    required this.busy,
  });

  final String name;
  final Color bg, surface, elevated, text, muted, accent, success, busy;

  /// The tint under a chip: the chip colour at a low alpha over the card.
  Color chip(Color c) => Color.alphaBlend(c.withValues(alpha: 0.22), surface);

  /// The selected tab pill: the accent over the glass bar.
  Color get tabBar => Color.alphaBlend(surface.withValues(alpha: 0.7), bg);
  Color get tabPill => Color.alphaBlend(accent.withValues(alpha: 0.24), tabBar);

  ColorScheme get scheme => SchemeController.builtIn(Brightness.dark).copyWith(
    surface: bg,
    surfaceContainerLowest: bg,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: elevated,
    surfaceContainerHighest: Color.alphaBlend(text.withValues(alpha: 0.06), elevated),
    onSurface: text,
    onSurfaceVariant: muted,
    primary: accent,
    onPrimary: bg,
    secondaryContainer: tabPill,
    onSecondaryContainer: text,
    outlineVariant: Color.alphaBlend(muted.withValues(alpha: 0.3), elevated),
  );

  /// Chip colours come from the palette, not from the hue nudge, so Success
  /// and Busy are what the candidate says they are.
  Semantic get semantic => Semantic.from(scheme).copyWith(
    open: success,
    onOpen: success,
    openContainer: chip(success),
    busy: busy,
    onBusy: busy,
    busyContainer: chip(busy),
  );

  ThemeData theme(ThemeData Function(ColorScheme) build) {
    final base = build(scheme);
    final others = base.extensions.values.where((e) => e is! Semantic);
    return base.copyWith(extensions: [...others, semantic]);
  }
}

Color _c(int rgb) => Color(0xFF000000 | rgb);

final paletteOptions = <PaletteOption>[
  PaletteOption('1-espresso-sand-apricot',
      bg: _c(0x140A08), surface: _c(0x2A1E1A), elevated: _c(0x3A2C27),
      text: _c(0xF2E6DE), muted: _c(0xC8B5AA), accent: _c(0xF3B08F),
      success: _c(0x6FA36A), busy: _c(0x8A7A3A)),
  PaletteOption('2-mocha-stone-sage',
      bg: _c(0x171311), surface: _c(0x2D2622), elevated: _c(0x3C342F),
      text: _c(0xF5EFEA), muted: _c(0xBFB2A8), accent: _c(0xD9B8A0),
      success: _c(0x7E9A72), busy: _c(0xB5965E)),
  PaletteOption('7-slate-brown-champagne',
      bg: _c(0x151312), surface: _c(0x23201E), elevated: _c(0x312D2A),
      text: _c(0xF7F2EC), muted: _c(0xBEB4AB), accent: _c(0xE2C2A2),
      success: _c(0x748B6D), busy: _c(0xB69A6B)),
  PaletteOption('recommended',
      bg: _c(0x140A08), surface: _c(0x2A1E1A), elevated: _c(0x382A25),
      text: _c(0xF2E6DE), muted: _c(0xC6B3A8), accent: _c(0xF3B08F),
      success: _c(0x6FA36A), busy: _c(0x9A7224)),
];
