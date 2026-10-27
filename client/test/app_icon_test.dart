/// Every section icon fits inside every container that draws it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/section_nav.dart';
import 'package:tigerhub/widgets/status_row.dart';

final _platforms = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});

Widget _wrap(Widget child, {double width = 390}) => MaterialApp(
  theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 844)),
    child: Scaffold(body: SizedBox(width: width, height: 844, child: child)),
  ),
);

final _circle = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle);

void _expectInsideCircle(WidgetTester tester, Finder circle, Finder icon) {
  final outer = tester.getRect(circle);
  final inner = tester.getRect(icon);
  expect(outer.contains(inner.topLeft) && outer.contains(inner.bottomRight - const Offset(0.001, 0.001)), isTrue, reason: '$inner outside $outer');
  // corners too, a square can fit the box and still poke out of the circle
  final radius = outer.shortestSide / 2;
  for (final corner in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
    final distance = (corner - outer.center).distance;
    expect(distance, lessThanOrEqualTo(radius), reason: '$corner outside the circle');
  }
}

// the Icon box stretches to its parent, the painted glyph is the RichText
Finder _glyph(Finder icon) => find.descendant(of: icon, matching: find.byType(RichText));

IconData _expected(AppIconKind kind) => debugDefaultTargetPlatformOverride == TargetPlatform.iOS ? kind.cupertino : kind.material;

void main() {
  testWidgets('section nav: 18 in the 42 circle', (tester) async {
    for (final kind in AppIconKind.values) {
      await tester.pumpWidget(_wrap(SectionScaffold(sections: [SectionSpec(id: kind.name, title: 'Title', subtitle: 'Subtitle', icon: Icons.circle, glyph: kind, builder: (_) => const SizedBox())])));
      final circle = _circle.first;
      final icon = find.descendant(of: circle, matching: find.byType(Icon));
      expect(tester.getSize(circle), const Size(42, 42));
      expect(tester.widget<Icon>(icon).icon, _expected(kind));
      expect(tester.getSize(_glyph(icon)), const Size(18, 18));
      _expectInsideCircle(tester, circle, _glyph(icon));
    }
  }, variant: _platforms);

  testWidgets('rows: 18 in 42, and 18 in 32 condensed', (tester) async {
    for (final dense in [false, true]) {
      for (final kind in AppIconKind.values) {
        await tester.pumpWidget(_wrap(Builder(builder: (context) => StatusRow(icon: kind.of(context), title: 'Title', subtitle: 'Subtitle', dense: dense))));
        final circle = _circle.first;
        final icon = find.descendant(of: circle, matching: find.byType(Icon));
        final side = dense ? StatusRow.denseBadgeSize : StatusRow.badgeSize;
        expect(tester.getSize(circle), Size(side, side));
        expect(tester.widget<Icon>(icon).icon, _expected(kind));
        expect(tester.getSize(_glyph(icon)), const Size(18, 18));
        _expectInsideCircle(tester, circle, _glyph(icon));
      }
    }
  }, variant: _platforms);

  testWidgets('card titles: the icon stays in its 22 slot', (tester) async {
    // phone header and the 600pt and wider one
    for (final width in [390.0, 700.0]) {
      for (final kind in AppIconKind.values) {
        await tester.pumpWidget(_wrap(CardShell(title: 'Title', glyph: kind, child: const SizedBox(height: 40)), width: width));
        final icon = find.byType(Icon);
        expect(tester.widget<Icon>(icon).icon, _expected(kind));
        final glyph = tester.getRect(_glyph(icon));
        expect(glyph.size, const Size(22, 22));
        final card = tester.getRect(find.byType(CardShell));
        final title = tester.getRect(find.text('Title'));
        expect(card.contains(glyph.topLeft) && card.contains(glyph.bottomRight), isTrue);
        // centred on the title line, not hanging off it
        expect(glyph.center.dy, inInclusiveRange(title.top, title.bottom));
      }
    }
  }, variant: _platforms);
}
