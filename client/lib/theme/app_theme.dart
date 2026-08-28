/// Theme.
///
/// The palette is not defined here. It arrives as a ColorScheme, either read
/// from the wallpaper-generated scheme file or built from the fallback seed,
/// and this file only decides how that scheme is applied.
///
/// Elevation is expressed only as surface tint. There are no drop shadows
/// anywhere in this app.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Rubik';

  /// Build the theme from whatever scheme is currently in force.
  static ThemeData from(ColorScheme scheme) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: scheme.brightness,
    );

    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
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
