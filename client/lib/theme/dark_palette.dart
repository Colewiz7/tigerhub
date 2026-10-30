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
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.secondary,
    required this.onSecondary,
    required this.pill,
    required this.onPill,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.outline,
    required this.outlineVariant,
    required this.success,
    required this.busy,
    this.closedTone = 59,
  });

  final String id;
  final String name;
  final Color bg, surface, elevated, text, muted, accent;

  /// Text and icons on a filled accent.
  final Color onAccent;

  /// Selected pickers and chips: a tint of the accent hue and its ink.
  final Color accentContainer, onAccentContainer;

  /// The second voice: toggles, secondary buttons.
  final Color secondary, onSecondary;

  /// The glass tab bar's selected pill and the label on it.
  final Color pill, onPill;

  /// The third voice, a neighbour of the accent hue.
  final Color tertiary, tertiaryContainer, onTertiaryContainer;

  /// Field borders and hairlines.
  final Color outline, outlineVariant;

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
    onAccent: Color(0xFF140A08),
    accentContainer: Color(0xFF703717),
    onAccentContainer: Color(0xFFFFDBCC),
    secondary: Color(0xFFE6BEAC),
    onSecondary: Color(0xFF432A1E),
    pill: Color(0xFF5C4033),
    onPill: Color(0xFFFFDBCC),
    tertiary: Color(0xFFD0C890),
    tertiaryContainer: Color(0xFF4D481C),
    onTertiaryContainer: Color(0xFFEDE4A9),
    outline: Color(0xFFA08D85),
    outlineVariant: Color(0xFF52443D),
    success: Color(0xFF81AF7D),
    busy: Color(0xFFC7942F),
  );

  static const mocha = DarkPalette(
    id: 'mocha',
    name: 'Mocha',
    bg: Color(0xFF151512),
    surface: Color(0xFF252622),
    elevated: Color(0xFF33342F),
    text: Color(0xFFF1EFE8),
    muted: Color(0xFFBCBAAE),
    accent: Color(0xFFA9C6BC),
    onAccent: Color(0xFF10201B),
    accentContainer: Color(0xFF33504A),
    onAccentContainer: Color(0xFFD2EDE4),
    secondary: Color(0xFFB7C4A8),
    onSecondary: Color(0xFF1F2A18),
    pill: Color(0xFF3F4B3C),
    onPill: Color(0xFFDCE8CF),
    tertiary: Color(0xFFD0BFA4),
    tertiaryContainer: Color(0xFF4F4430),
    onTertiaryContainer: Color(0xFFF0E1C6),
    outline: Color(0xFF8E9086),
    outlineVariant: Color(0xFF4A4C44),
    success: Color(0xFF9CB193),
    busy: Color(0xFFC3AB7D),
    closedTone: 63,
  );

  static const slate = DarkPalette(
    id: 'slate',
    name: 'Slate',
    bg: Color(0xFF121417),
    surface: Color(0xFF1F2227),
    elevated: Color(0xFF2B2F35),
    text: Color(0xFFEEF1F5),
    muted: Color(0xFFB8BFCA),
    accent: Color(0xFF8AB4F8),
    onAccent: Color(0xFF0A1A33),
    accentContainer: Color(0xFF1F3C6E),
    onAccentContainer: Color(0xFFD6E4FF),
    secondary: Color(0xFFA8C0E8),
    onSecondary: Color(0xFF12233F),
    pill: Color(0xFF2E4468),
    onPill: Color(0xFFD6E4FF),
    tertiary: Color(0xFFC3B9F2),
    tertiaryContainer: Color(0xFF3F376B),
    onTertiaryContainer: Color(0xFFE6E0FF),
    outline: Color(0xFF8A919C),
    outlineVariant: Color(0xFF444A54),
    success: Color(0xFF91A58C),
    busy: Color(0xFFBDA379),
  );

  // true black page, iOS grey steps for cards, no shadows
  static const midnightBlue = DarkPalette(
    id: 'midnight_blue',
    name: 'Midnight blue',
    bg: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    elevated: Color(0xFF2B2D32),
    text: Color(0xFFF5F5F7),
    muted: Color(0xFFAEAEB2),
    accent: Color(0xFF5AA9FF),
    onAccent: Color(0xFF000000),
    accentContainer: Color(0xFF0B3A75),
    onAccentContainer: Color(0xFFD6E7FF),
    secondary: Color(0xFF7FB5FF),
    onSecondary: Color(0xFF001B3D),
    pill: Color(0xFF0F2C57),
    onPill: Color(0xFFD6E7FF),
    tertiary: Color(0xFFA8B8FF),
    tertiaryContainer: Color(0xFF2A3166),
    onTertiaryContainer: Color(0xFFE0E4FF),
    outline: Color(0xFF8C9097),
    outlineVariant: Color(0xFF383C44),
    success: Color(0xFF7DBE80),
    busy: Color(0xFFD2A448),
  );

  static const midnightOrange = DarkPalette(
    id: 'midnight_orange',
    name: 'Midnight orange',
    bg: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    elevated: Color(0xFF2E2C2A),
    text: Color(0xFFF5F5F7),
    muted: Color(0xFFAEAEB2),
    accent: Color(0xFFFF9F5A),
    onAccent: Color(0xFF000000),
    accentContainer: Color(0xFF6B300A),
    onAccentContainer: Color(0xFFFFDCC4),
    secondary: Color(0xFFF0B48A),
    onSecondary: Color(0xFF3A1D08),
    pill: Color(0xFF5A2D12),
    onPill: Color(0xFFFFDCC4),
    tertiary: Color(0xFFD9C27A),
    tertiaryContainer: Color(0xFF4A3F14),
    onTertiaryContainer: Color(0xFFF0E2A8),
    outline: Color(0xFF938D88),
    outlineVariant: Color(0xFF403A36),
    success: Color(0xFF7DBE80),
    busy: Color(0xFFD2A448),
  );

  static const all = [espresso, mocha, slate, midnightBlue, midnightOrange];

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
    onPrimary: onAccent,
    primaryContainer: accentContainer,
    onPrimaryContainer: onAccentContainer,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: pill,
    onSecondaryContainer: onPill,
    tertiary: tertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    outline: outline,
    outlineVariant: outlineVariant,
    surfaceTint: accent,
    inversePrimary: accentContainer,
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
