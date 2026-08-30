/// The custom section glyphs.
///
/// Codex's set, adopted per `docs/glyph-adoption-spec.md`. The important half
/// of that decision is where they are **not** used: not the tab bar, not
/// actions like copy or close, and not venue or event rows. They carry section
/// identity, and swapping every Material icon for them would change the style
/// without reducing the repetition that made row icons dull in the first place.
///
/// Rendered at 24px with `currentColor`, which the spec asks for and which is
/// also a trap: flutter_svg paints `currentColor` black by default, and on a
/// near-black surface that is invisible. So the colour is always resolved here
/// rather than being left to the call site, and `test/svg_theming_test.dart`
/// fails anything that renders one of these without a theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The glyphs that exist, named as the spec's mapping table names them.
enum GlyphKind {
  dining('dining'),
  events('events'),
  calendar('calendar'),
  housing('housing'),
  postOffice('post-office'),
  makerspace('makerspace'),
  buildings('buildings'),
  market('market'),
  visitingChef('visiting-chef');

  const GlyphKind(this.asset);

  final String asset;

  String get path => 'assets/generated/glyphs/$asset.svg';
}

class Glyph extends StatelessWidget {
  const Glyph(this.kind, {super.key, this.size = 24, this.color});

  final GlyphKind kind;
  final double size;

  /// Defaults to the surrounding text colour. The spec says not to tint a
  /// glyph independently of the label it identifies, so this exists for the
  /// case where the label itself is tinted, not to give the glyph its own hue.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;

    return SvgPicture.asset(
      kind.path,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: resolved),
      // The label beside it says what the section is, so announcing the glyph
      // as well would say it twice.
      excludeFromSemantics: true,
    );
  }
}
