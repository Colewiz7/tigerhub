/// WCAG contrast ratios and a hex adjuster. Test only.
library;

import 'package:flutter/material.dart';

double luminance(Color c) => c.computeLuminance();

double ratio(Color fg, Color bg) {
  final a = luminance(fg), b = luminance(bg);
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

String hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// The closest colour to [fg], same hue and saturation, that reaches [min]
/// against [bg]. Moves lightness away from the background.
Color adjustToContrast(Color fg, Color bg, {double min = 4.5}) {
  if (ratio(fg, bg) >= min) return fg;
  final hsl = HSLColor.fromColor(fg);
  final lighten = luminance(bg) < 0.5;
  for (var i = 1; i <= 100; i++) {
    final l = (hsl.lightness + (lighten ? i : -i) / 100).clamp(0.0, 1.0);
    final next = hsl.withLightness(l).toColor();
    if (ratio(next, bg) >= min) return next;
  }
  return lighten ? Colors.white : Colors.black;
}
