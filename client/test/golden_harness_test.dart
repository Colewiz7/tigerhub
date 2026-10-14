import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'golden_harness.dart';
import 'known_overflows.dart';

const _strip = ExpectedOverflow('lib/widgets/campus_map.dart:900', 'bottom', 24);

Overflow _seen({
  double px = 24,
  String side = 'bottom',
  String where = 'lib/widgets/campus_map.dart:900',
  String instance = 'RenderFlex#a',
}) =>
    Overflow(px, side, where, instance);

Widget _overflowingRow() => const SizedBox(
      width: 100,
      child: Row(children: [SizedBox(width: 150, height: 10)]),
    );

void main() {
  group('overflowProblems', () {
    test('an exact match is clean, within 0.5px', () {
      expect(overflowProblems([_seen()], [_strip]), isEmpty);
      expect(overflowProblems([_seen(px: 24.4)], [_strip]), isEmpty);
    });

    test('a second overflow with the same size and place cannot hide', () {
      final problems = overflowProblems(
        [_seen(), _seen(instance: 'RenderFlex#b')],
        [_strip],
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('expects 1'));
      expect(problems.single, contains('produced 2'));
    });

    test('a listed count of two needs two', () {
      const two = ExpectedOverflow('lib/widgets/campus_map.dart:900', 'bottom', 24, count: 2);
      expect(
        overflowProblems([_seen(), _seen(instance: 'RenderFlex#b')], [two]),
        isEmpty,
      );
      expect(overflowProblems([_seen()], [two]), hasLength(1));
    });

    test('a new overflow at another line fails', () {
      final problems = overflowProblems(
        [_seen(), _seen(where: 'lib/widgets/other.dart:10')],
        [_strip],
      );
      expect(problems.single, contains('Unexpected'));
      expect(problems.single, contains('other.dart:10'));
    });

    test('the same line on another edge or by another size fails', () {
      expect(overflowProblems([_seen(side: 'right')], [_strip]), hasLength(2));
      expect(overflowProblems([_seen(px: 25)], [_strip]), hasLength(2));
    });

    test('a listed overflow that disappears fails', () {
      final problems = overflowProblems([], [_strip]);
      expect(problems.single, contains('produced 0'));
    });

    test('any overflow in a test with no entry fails', () {
      expect(overflowProblems([_seen()], []), hasLength(1));
      expect(overflowProblems([], []), isEmpty);
    });
  });

  group('staleKnownEntries', () {
    const known = {
      'present': KnownOverflow('a_test.dart', [_strip], 'fix'),
      'renamed away': KnownOverflow('a_test.dart', [_strip], 'fix'),
      'other file': KnownOverflow('b_test.dart', [_strip], 'fix'),
    };

    test('names a listed test the file no longer defines', () {
      expect(staleKnownEntries('a_test.dart', {'present'}, known), ['renamed away']);
    });

    test('is clean when every listed test of the file is defined', () {
      expect(
        staleKnownEntries('a_test.dart', {'present', 'renamed away'}, known),
        isEmpty,
      );
    });
  });

  group('captureOverflows', () {
    testWidgets('catches a real overflow with its edge, size and source line', (tester) async {
      final seen = await captureOverflows(() => tester.pumpWidget(
            MaterialApp(home: Scaffold(body: _overflowingRow())),
          ));
      expect(seen, hasLength(1));
      expect(seen.single.pixels, 50);
      expect(seen.single.side, 'right');
      expect(seen.single.where, startsWith('test/golden_harness_test.dart:'));
    });

    testWidgets('counts one render object once however often it relays out', (tester) async {
      final seen = await captureOverflows(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: _overflowingRow())));
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: _overflowingRow())));
        await tester.binding.setSurfaceSize(const Size(500, 500));
        await tester.pump();
        await tester.binding.setSurfaceSize(null);
      });
      expect(seen, hasLength(1));
    });

    testWidgets('counts two overflowing render objects twice', (tester) async {
      final seen = await captureOverflows(() => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(children: [_overflowingRow(), _overflowingRow()]),
              ),
            ),
          ));
      expect(seen, hasLength(2));
      expect(
        overflowProblems(seen, [
          ExpectedOverflow(seen.first.where, 'right', 50),
        ]),
        isNotEmpty,
        reason: 'a list entry of one cannot absorb two overflows',
      );
    });
  });

  test('the app theme still lacks fontFamily, so goldenTheme is still needed', () {
    final t = AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))).textTheme;
    final slots = [
      t.displayLarge, t.displayMedium, t.displaySmall,
      t.headlineLarge, t.headlineMedium, t.headlineSmall,
      t.titleLarge, t.titleMedium, t.titleSmall,
      t.bodyLarge, t.bodyMedium, t.bodySmall,
      t.labelLarge, t.labelMedium, t.labelSmall,
    ];
    expect(
      slots.any((s) => s?.fontFamily == null),
      isTrue,
      reason: 'AppTheme text slots now carry fontFamily: the defect goldenTheme() '
          'masks is fixed. Delete goldenTheme() and its calls in the golden tests, '
          'delete this test, and regenerate the goldens.',
    );
  });
}
