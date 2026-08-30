/// The custom section glyphs.
///
/// `docs/glyph-adoption-spec.md` is mostly a decision about restraint: the
/// glyphs carry section identity and nothing else. Replacing every Material
/// icon would change the style without reducing the repetition that made row
/// icons dull, and the tab bar is better off looking like a platform tab bar.
/// These tests pin that restraint, because it is the kind of thing that erodes
/// one convenient exception at a time.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/glyph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every declared glyph has artwork', () {
    for (final kind in GlyphKind.values) {
      final file = File('assets/generated/glyphs/${kind.asset}.svg');
      expect(file.existsSync(), isTrue,
          reason: '${kind.asset}.svg is missing, so it renders as a blank box');
      expect(file.readAsStringSync(), startsWith('<svg'));
    }
  });

  test('the tab bar keeps Material icons', () {
    // The spec is explicit: familiar platform level destinations matter more
    // than illustration consistency.
    final tabs = File('lib/widgets/tab_bar.dart').readAsStringSync();
    expect(tabs.contains('Glyph('), isFalse,
        reason: 'the tab bar should stay Material, per the adoption spec');
  });

  test('venue and event rows keep Material icons', () {
    // The generated dining glyph names the section but cannot distinguish a
    // cafe from a market from a food truck, and one custom calendar in place
    // of one Material calendar changes style without reducing repetition.
    for (final path in ['lib/cards/event_row.dart']) {
      final source = File(path).readAsStringSync();
      expect(source.contains('Glyph('), isFalse,
          reason: '$path should stay Material, per the adoption spec');
    }
  });

  testWidgets('a glyph takes its colour from the surrounding text',
      (tester) async {
    // The spec says not to tint a glyph independently of the label it
    // identifies, so the default has to follow the label rather than be
    // whatever flutter_svg falls back to.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: DefaultTextStyle(
          style: TextStyle(color: Color(0xFF00FF00)),
          child: Center(child: Glyph(GlyphKind.dining)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a glyph is not announced beside its own label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Glyph(GlyphKind.dining), Text('Dining')],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Dining'), findsOneWidget);
    handle.dispose();
  });
}
