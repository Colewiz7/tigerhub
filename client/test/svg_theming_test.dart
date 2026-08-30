/// Every SVG that paints with `currentColor` must be given a theme.
///
/// This is a trap rather than a mistake anyone makes once. flutter_svg defaults
/// `currentColor` to **black**, so art that was drawn to follow the theme
/// instead renders black, and on this app's near-black surfaces that means it
/// vanishes. Nothing throws, the widget still lays out, and the only symptom is
/// that something is missing.
///
/// It already happened once, to the "Hub" half of the wordmark. Ten glyphs
/// under `assets/generated/glyphs/` use `currentColor` too and are not wired
/// into any screen yet, so this guard exists for whoever wires them.
///
/// The check is deliberately coarse: it works per file rather than per call
/// site, because parsing Dart properly to find one argument is far more
/// machinery than the problem deserves. A false pass is possible; a silent
/// black-on-black asset is not.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every widget rendering a currentColor asset passes a theme', () {
    final dart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final offenders = <String>[];

    for (final file in dart) {
      final source = file.readAsStringSync();
      if (!source.contains('SvgPicture')) continue;

      // Every asset path this file renders.
      final assets = RegExp(r"'(assets/[^']+\.svg)'")
          .allMatches(source)
          .map((m) => m.group(1)!);

      final needsTheme = assets.any((path) {
        final asset = File(path);
        return asset.existsSync() &&
            asset.readAsStringSync().contains('currentColor');
      });

      if (needsTheme && !source.contains('theme:')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'these render art painted with currentColor but pass no '
            'SvgTheme, so flutter_svg will paint it black: $offenders');
  });

  test('the glyphs really do rely on currentColor', () {
    // If this ever stops being true the guard above is not testing anything,
    // so it is worth knowing rather than quietly passing forever.
    final glyphs = Directory('assets/generated/glyphs')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'));

    expect(glyphs, isNotEmpty);
    for (final glyph in glyphs) {
      expect(glyph.readAsStringSync(), contains('currentColor'),
          reason: '${glyph.path} no longer follows the theme');
    }
  });
}
