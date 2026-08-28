/// Theme.
///
/// The palette is generated from one warm seed, the way a matugen scheme is,
/// so the whole app is a rendering of that scheme rather than a set of
/// hand-picked colours. Surfaces are then pinned to explicitly warm values,
/// because Material's own dark surfaces drift toward neutral grey.
///
/// Elevation is expressed only as surface tint. There are no drop shadows
/// anywhere in this app.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

class AppTheme {
  const AppTheme._();

  /// RIT orange. The single seed the rest of the scheme is generated from.
  static const Color seed = Color(0xFFF76902);

  static const String fontFamily = 'Rubik';

  // Warm near-black. Red channel leads at every step, so the background reads
  // as warm rather than as neutral grey.
  static const _darkSurfaces = _Surfaces(
    lowest: Color(0xFF0E0B09),
    low: Color(0xFF15110E),
    base: Color(0xFF1C1714),
    high: Color(0xFF251E1A),
    highest: Color(0xFF2F2721),
  );

  static const _lightSurfaces = _Surfaces(
    lowest: Color(0xFFFFFFFF),
    low: Color(0xFFFBF5F0),
    base: Color(0xFFF6EEE7),
    high: Color(0xFFF0E6DD),
    highest: Color(0xFFEADDD2),
  );

  static ThemeData dark() => _build(Brightness.dark, _darkSurfaces);
  static ThemeData light() => _build(Brightness.light, _lightSurfaces);

  static ThemeData _build(Brightness brightness, _Surfaces surfaces) {
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final scheme = generated.copyWith(
      surface: surfaces.base,
      surfaceContainerLowest: surfaces.lowest,
      surfaceContainerLow: surfaces.low,
      surfaceContainer: surfaces.base,
      surfaceContainerHigh: surfaces.high,
      surfaceContainerHighest: surfaces.highest,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    );

    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return base.copyWith(
      scaffoldBackgroundColor: surfaces.lowest,
      // Shadows are disabled globally rather than per widget, so a stray
      // elevation cannot reintroduce one.
      shadowColor: Colors.transparent,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: Shapes.card),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        space: 1,
        thickness: 1,
      ),
      textTheme: TextTheme(
        // The one oversized, light-weight number per card.
        displayLarge: TextStyle(
          fontSize: 52,
          height: 1.0,
          fontVariations: Weights.light,
          letterSpacing: -1.5,
          color: onSurface,
        ),
        displayMedium: TextStyle(
          fontSize: 34,
          height: 1.05,
          fontVariations: Weights.light,
          letterSpacing: -0.8,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 17,
          fontVariations: Weights.medium,
          letterSpacing: 0.1,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 14.5,
          fontVariations: Weights.medium,
          color: onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          fontVariations: Weights.regular,
          color: onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontVariations: Weights.regular,
          color: muted,
        ),
        // Small, muted, wide. The label under a big number.
        labelSmall: TextStyle(
          fontSize: 10.5,
          fontVariations: Weights.medium,
          letterSpacing: 1.1,
          color: muted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: Shapes.inner,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Shapes.inner,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Shapes.inner,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _Surfaces {
  const _Surfaces({
    required this.lowest,
    required this.low,
    required this.base,
    required this.high,
    required this.highest,
  });

  final Color lowest;
  final Color low;
  final Color base;
  final Color high;
  final Color highest;
}
