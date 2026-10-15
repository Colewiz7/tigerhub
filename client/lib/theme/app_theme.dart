/// Theme.
///
/// The palette is not defined here. It arrives as a ColorScheme, either read
/// from the wallpaper-generated scheme file or built from the fallback seed,
/// and this file only decides how that scheme is applied.
///
/// Elevation is expressed only as surface tint. There are no drop shadows
/// anywhere in this app.
library;

import 'package:flutter/cupertino.dart' show CupertinoTextThemeData, CupertinoThemeData;
import 'package:flutter/material.dart';

import 'semantic.dart';
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
      // Status colours harmonized against this scheme, so they never clash
      // with a wallpaper derived palette.
      extensions: <ThemeExtension<dynamic>>[Semantic.from(scheme)],
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
      // Merged onto the base text theme, which already carries Rubik on all 15
      // slots. Passing a bare TextTheme here would replace it and drop the
      // family from every slot this file does not restyle.
      textTheme: base.textTheme.merge(TextTheme(
        // The one oversized, light-weight number per card.
        displayLarge: TextStyle(
          fontSize: 68,
          height: 1.0,
          fontVariations: Weights.light,
          letterSpacing: -1.5,
          color: onSurface,
        ),
        displayMedium: TextStyle(
          fontSize: 46,
          height: 1.05,
          fontVariations: Weights.light,
          letterSpacing: -0.8,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 27,
          fontVariations: Weights.semibold,
          letterSpacing: 0.1,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontVariations: Weights.medium,
          color: onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 17,
          height: 1.4,
          fontVariations: Weights.regular,
          color: onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 14.5,
          fontVariations: Weights.regular,
          color: muted,
        ),
        // Small, muted, wide. The label under a big number.
        labelSmall: TextStyle(
          fontSize: 12.5,
          fontVariations: Weights.medium,
          letterSpacing: 1.1,
          color: muted,
        ),
      )),
      cupertinoOverrideTheme: _cupertino(scheme),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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

  /// The Cupertino text styles default to the platform system font, so any
  /// Cupertino widget (the iOS path) would ignore Rubik. Each style keeps its
  /// iOS size, weight and colour and only swaps the family.
  static CupertinoThemeData _cupertino(ColorScheme scheme) {
    final d = CupertinoTextThemeData(primaryColor: scheme.primary);
    TextStyle rubik(TextStyle s) => s.copyWith(fontFamily: fontFamily);
    return CupertinoThemeData(
      textTheme: CupertinoTextThemeData(
        primaryColor: scheme.primary,
        textStyle: rubik(d.textStyle),
        actionTextStyle: rubik(d.actionTextStyle),
        actionSmallTextStyle: rubik(d.actionSmallTextStyle),
        tabLabelTextStyle: rubik(d.tabLabelTextStyle),
        navTitleTextStyle: rubik(d.navTitleTextStyle),
        navLargeTitleTextStyle: rubik(d.navLargeTitleTextStyle),
        navActionTextStyle: rubik(d.navActionTextStyle),
        pickerTextStyle: rubik(d.pickerTextStyle),
        dateTimePickerTextStyle: rubik(d.dateTimePickerTextStyle),
      ),
    );
  }
}
