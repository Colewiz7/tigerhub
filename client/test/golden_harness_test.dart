import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      ('a_test.dart', 'present'): KnownOverflow([_strip], 'fix'),
      ('a_test.dart', 'renamed away'): KnownOverflow([_strip], 'fix'),
      ('b_test.dart', 'other file'): KnownOverflow([_strip], 'fix'),
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

  group('knownFor', () {
    const known = {
      ('a_test.dart', 'same name'): KnownOverflow([_strip], 'fix'),
    };

    test('finds the entry for its own file', () {
      expect(knownFor('a_test.dart', 'same name', known: known), isNotNull);
    });

    test('a same-named test in another file gets no entry, so its overflow fails', () {
      final entry = knownFor('b_test.dart', 'same name', known: known);
      expect(entry, isNull);
      expect(overflowProblems([_seen()], entry?.overflows ?? const []), isNotEmpty);
    });
  });

  group('callerFile', () {
    test('skips the harness frames and names the calling test file', () {
      const trace = '#0      goldenWidgets (file:///x/client/test/golden_harness.dart:122:3)\n'
          '#1      main (file:///x/client/test/map_screen_golden_test.dart:70:9)\n';
      expect(callerFile(trace), 'map_screen_golden_test.dart');
    });
  });

  group('goldenUseProblems', () {
    test('a golden in plain testWidgets is a violation', () {
      const source = '''
void main() {
  testWidgets('a', (tester) async {
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/a.png'));
  });
}
''';
      final problems = goldenUseProblems(source);
      expect(problems, hasLength(1));
      expect(problems.single, contains('line 2'));
    });

    test('a png compared through expectLater in plain testWidgets is a violation', () {
      const source = "testWidgets('a', (t) async { await expectLater(x, y('goldens/a.png')); });";
      expect(goldenUseProblems(source), hasLength(1));
    });

    test('goldenWidgets is fine, and a plain test beside it is not blamed', () {
      const source = '''
void main() {
  goldenWidgets('a', (tester) async {
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/a.png'));
  });
  testWidgets('plain', (tester) async {
    expect(find.text('x'), findsNothing);
  });
}
''';
      expect(goldenUseProblems(source), isEmpty);
    });

    test('the real test files obey it', () {
      final problems = <String>[];
      for (final file in Directory('test').listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        // This file holds the violating fixtures above as string literals.
        if (!name.endsWith('_test.dart') || name == 'golden_harness_test.dart') continue;
        for (final problem in goldenUseProblems(file.readAsStringSync())) {
          problems.add('$name $problem');
        }
      }
      expect(problems, isEmpty);
    });
  });

  goldenWidgets('the harness registers the file that calls it', (tester) async {
    await tester.pumpWidget(const SizedBox());
  });

  test('goldenWidgets registered its calling file by itself', () {
    expect(goldenFilesRegistered, contains('golden_harness_test.dart'));
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
}
