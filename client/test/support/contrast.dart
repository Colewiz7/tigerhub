/// WCAG contrast ratios. Test only.
library;

import 'package:flutter/material.dart';

double ratio(Color fg, Color bg) {
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

String hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
