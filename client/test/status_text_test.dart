/// Only the clock time in a status line is highlighted, never "until" or "Opens".
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/status_row.dart';
import 'package:tigerhub/widgets/status_text.dart';

const _seed = Color(0xFFF76902);

ThemeData _theme(Brightness b) => AppTheme.from(ColorScheme.fromSeed(seedColor: _seed, brightness: b));

Color _over(Color top, Color under) => Color.alphaBlend(top, under);

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('which part is a time', () {
    String? only(String text) {
      final ranges = StatusText.timeRanges(text);
      return ranges.length == 1 ? text.substring(ranges.single.start, ranges.single.end) : null;
    }

    test('the time, not the word before it', () {
      expect(only('Open until 10 PM'), '10 PM');
      expect(only('Opens 7 AM'), '7 AM');
      expect(only('Closes at midnight'), 'midnight');
      expect(only('Open · until 10:30 PM'), '10:30 PM');
      expect(only('from noon'), 'noon');
    });

    test('a range highlights both ends and not the "to"', () {
      const text = 'Italian • 11 a.m. to 2 p.m.';
      expect([for (final r in StatusText.timeRanges(text)) text.substring(r.start, r.end)], ['11 a.m.', '2 p.m.']);
    });

    test('text with no time has nothing to highlight', () {
      expect(StatusText.timeRanges('Open · hours unavailable'), isEmpty);
      expect(StatusText.timeRanges('5 amazing places'), isEmpty);
      expect(StatusText.timeRanges('Closed today'), isEmpty);
    });
  });

  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1, Brightness b = Brightness.light}) =>
      tester.pumpWidget(MaterialApp(
        theme: _theme(b),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
        ),
      ));

  StatusTextPainter painterOf(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.descendant(of: find.byType(StatusText), matching: find.byType(CustomPaint)).first).painter!
          as StatusTextPainter;

  testWidgets('the pill sits behind the time and leaves "until" bare', (tester) async {
    await pump(tester, const StatusText('Open until 10 PM'));
    final text = find.text('Open until 10 PM');
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final size = tester.getSize(text);
    final rects = painterOf(tester).highlights(size);
    expect(rects, hasLength(1));

    final time = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 11, extentOffset: 16)).single.toRect();
    final until = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 5, extentOffset: 10)).single.toRect();
    expect(rects.single.left, lessThan(time.left));
    expect(rects.single.right, greaterThan(time.right));
    expect(rects.single.left, greaterThan(until.right), reason: 'the pill does not reach back into the word');
  });

  testWidgets('one plain Text keeps one spoken sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const StatusText('Open until 10 PM'));
    expect(find.bySemanticsLabel('Open until 10 PM'), findsOneWidget);
    expect(find.text('Open until 10 PM'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('text with no time is a plain Text', (tester) async {
    await pump(tester, const StatusText('Closed today'));
    expect(find.descendant(of: find.byType(StatusText), matching: find.byType(CustomPaint)), findsNothing);
  });

  for (final brightness in Brightness.values) {
    test('the text keeps 4.5:1 on the tint in ${brightness.name}', () {
      final scheme = _theme(brightness).colorScheme;
      final tint = StatusText.tint(scheme);
      final surfaces = [
        scheme.surface,
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
      ];
      for (final surface in surfaces) {
        final under = _over(tint, surface);
        expect(_ratio(scheme.onSurface, under), greaterThanOrEqualTo(4.5));
        expect(_ratio(scheme.onSurfaceVariant, under), greaterThanOrEqualTo(4.5));
      }
    });
  }

  testWidgets('wrapped at 2x on 390 wide, no overflow and every time still gets a pill', (tester) async {
    for (final b in Brightness.values) {
      await pump(
        tester,
        const Column(
          children: [
            StatusRow(
              dense: true,
              icon: AppIconKind.dining,
              title: 'Gracie’s',
              subtitle: 'Open · until 10:30 PM',
              subtitleMaxLines: null,
            ),
            StatusText('Italian • 11:00 AM to 2:00 PM • Global Village Plaza'),
          ],
        ),
        scale: 2,
        b: b,
      );
      expect(tester.takeException(), isNull);
      final painters = tester.widgetList<CustomPaint>(find.descendant(of: find.byType(StatusText), matching: find.byType(CustomPaint)));
      expect(painters, isNotEmpty);
      final wrapped = painters.last.painter! as StatusTextPainter;
      final size = tester.getSize(find.text('Italian • 11:00 AM to 2:00 PM • Global Village Plaza'));
      expect(wrapped.highlights(size).length, greaterThanOrEqualTo(2));
    }
  });
}
