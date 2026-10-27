/// Every app icon fits inside every container that draws it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/empty_state.dart';
import 'package:tigerhub/widgets/section_nav.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

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

// cupertino has no food, drink, wheelchair, bicycle or baby glyphs
const _materialOnIos = {
  AppIconKind.drink,
  AppIconKind.accessibleEntrance,
  AppIconKind.lactation,
  AppIconKind.dining,
  AppIconKind.cutlery,
  AppIconKind.menu,
  AppIconKind.visitingChef,
  AppIconKind.roomService,
  AppIconKind.cafe,
  AppIconKind.iceCream,
  AppIconKind.salad,
  AppIconKind.breakfast,
  AppIconKind.bakery,
  AppIconKind.accessible,
  AppIconKind.bike,
  AppIconKind.changingTable,
};

// advances vary per glyph, the ink test covers the fit
void _expectGlyphSize(Size glyph, double size) {
  expect(glyph.height, size);
  expect(glyph.width, greaterThan(0));
}

// every painted pixel, not the layout box, cupertino glyphs overshoot their em
Future<void> _expectInkInsideCircle(WidgetTester tester, IconData icon, double size, double circle) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox.square(dimension: circle, child: Center(child: Icon(icon, size: size, color: const Color(0xFF000000)))),
      ),
    ),
  ));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  final side = (circle * 3).round();
  final centre = side / 2;
  var inked = 0;
  var worst = 0.0;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      if (bytes!.getUint8((y * side + x) * 4 + 3) < 32) continue;
      inked++;
      worst = math.max(worst, math.sqrt(math.pow(x + 0.5 - centre, 2) + math.pow(y + 0.5 - centre, 2)));
    }
  }
  expect(inked, greaterThan(0), reason: 'nothing painted for $icon');
  expect(worst / 3, lessThanOrEqualTo(circle / 2), reason: '$icon reaches ${worst / 3} from the centre of a $circle circle');
}

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('ink stays inside every circle, both platforms', (tester) async {
    for (final kind in AppIconKind.values) {
      for (final icon in {kind.cupertino, kind.material}) {
        await _expectInkInsideCircle(tester, icon, 18, StatusRow.badgeSize);
        await _expectInkInsideCircle(tester, icon, 18, StatusRow.denseBadgeSize);
      }
    }
    for (final kind in EmptyKind.values) {
      for (final icon in {kind.icon.cupertino, kind.icon.material}) {
        await _expectInkInsideCircle(tester, icon, 29, 58);
        await _expectInkInsideCircle(tester, icon, 38, 76);
      }
    }
  });

  test('iOS draws from CupertinoIcons except where it has no glyph', () {
    for (final kind in AppIconKind.values) {
      final family = _materialOnIos.contains(kind) ? 'MaterialIcons' : 'CupertinoIcons';
      expect(kind.cupertino.fontFamily, family, reason: kind.name);
      expect(kind.material.fontFamily, 'MaterialIcons', reason: kind.name);
    }
  });

  testWidgets('section nav: 18 in the 42 circle', (tester) async {
    for (final kind in AppIconKind.values) {
      await tester.pumpWidget(_wrap(SectionScaffold(sections: [SectionSpec(id: kind.name, title: 'Title', subtitle: 'Subtitle', icon: kind, builder: (_) => const SizedBox())])));
      final circle = _circle.first;
      final icon = find.descendant(of: circle, matching: find.byType(Icon));
      expect(tester.getSize(circle), const Size(42, 42));
      expect(tester.widget<Icon>(icon).icon, _expected(kind));
      _expectGlyphSize(tester.getSize(_glyph(icon)), 18);
      _expectInsideCircle(tester, circle, _glyph(icon));
    }
  }, variant: _platforms);

  testWidgets('rows: 18 in 42, and 18 in 32 condensed', (tester) async {
    for (final dense in [false, true]) {
      for (final kind in AppIconKind.values) {
        await tester.pumpWidget(_wrap(StatusRow(icon: kind, title: 'Title', subtitle: 'Subtitle', dense: dense)));
        final circle = _circle.first;
        final icon = find.descendant(of: circle, matching: find.byType(Icon));
        final side = dense ? StatusRow.denseBadgeSize : StatusRow.badgeSize;
        expect(tester.getSize(circle), Size(side, side));
        expect(tester.widget<Icon>(icon).icon, _expected(kind));
        _expectGlyphSize(tester.getSize(_glyph(icon)), 18);
        _expectInsideCircle(tester, circle, _glyph(icon));
      }
    }
  }, variant: _platforms);

  testWidgets('empty states: 29 in 58, 38 in 76', (tester) async {
    for (final compact in [true, false]) {
      for (final kind in EmptyKind.values) {
        await tester.pumpWidget(_wrap(EmptyState(kind: kind, compact: compact)));
        final circle = _circle.first;
        final icon = find.descendant(of: circle, matching: find.byType(Icon));
        expect(tester.getSize(circle), compact ? const Size(58, 58) : const Size(76, 76));
        expect(tester.widget<Icon>(icon).icon, _expected(kind.icon));
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
        _expectGlyphSize(glyph.size, 22);
        final card = tester.getRect(find.byType(CardShell));
        final title = tester.getRect(find.text('Title'));
        expect(card.contains(glyph.topLeft) && card.contains(glyph.bottomRight), isTrue);
        // centred on the title line, not hanging off it
        expect(glyph.center.dy, inInclusiveRange(title.top, title.bottom));
      }
    }
  }, variant: _platforms);
}
