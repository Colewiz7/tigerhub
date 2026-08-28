/// Modern newspaper: masthead, rules, serif display type, strong hierarchy,
/// generous whitespace, on an otherwise modern app. Not a newsprint pastiche,
/// so no paper texture, no sepia, no fake halftone.
library;

import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const Color ink = Color(0xFF111111);
  static const Color paper = Color(0xFFFAF8F5);
  static const Color rule = Color(0xFFD8D3CC);
  static const Color accent = Color(0xFFF76902); // RIT orange, used sparingly
  static const Color muted = Color(0xFF6B6560);
  static const Color warning = Color(0xFFA85B00);

  static const Color inkDark = Color(0xFFEDEAE5);
  static const Color paperDark = Color(0xFF161513);
  static const Color ruleDark = Color(0xFF33302C);
  static const Color mutedDark = Color(0xFF9A938C);
  static const Color warningDark = Color(0xFFE0A050);

  /// A serif for display type only. Body stays in the system sans, which keeps
  /// the newspaper cue in the hierarchy rather than in a costume.
  static const String displayFont = 'serif';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final fg = isDark ? inkDark : ink;
    final bg = isDark ? paperDark : paper;
    final line = isDark ? ruleDark : rule;

    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      ).copyWith(surface: bg, onSurface: fg),
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
      cardTheme: CardThemeData(
        elevation: 0,
        color: bg,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: line),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: TextStyle(
          fontFamily: displayFont,
          fontSize: 34,
          height: 1.05,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: fg,
        ),
        titleLarge: TextStyle(
          fontFamily: displayFont,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: fg),
        bodySmall: TextStyle(fontSize: 12, color: isDark ? mutedDark : muted),
        labelSmall: TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: isDark ? mutedDark : muted,
        ),
      ),
    );
  }

  static Color mutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? mutedDark : muted;

  static Color warningOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? warningDark : warning;

  static Color ruleOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? ruleDark : rule;
}
