/// Shared harness for every test that takes a golden.
///
/// Two jobs. It loads the real fonts, so a golden shows Rubik and the real
/// icon glyphs and the text metrics are the shipping ones, not Ahem blocks.
/// And it fails the test on any layout overflow that is not listed in
/// known_overflows.dart; overflows are never swallowed or printed.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_overflows.dart';

Future<void>? _fontsLoaded;

/// Loads every font the app bundle declares (Rubik, Space Grotesk,
/// MaterialIcons, CupertinoIcons) under the family names the app asks for.
Future<void> loadGoldenFonts() => _fontsLoaded ??= _loadFonts();

Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest) {
    final family = (entry as Map<String, dynamic>)['family'] as String;
    final loader = FontLoader(family);
    for (final font in entry['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load((font as Map<String, dynamic>)['asset'] as String));
    }
    await loader.load();
  }
}

/// Call once from main() of any file that takes goldens, naming that file
/// (its basename, as in known_overflows.dart).
void setUpGoldenFonts(String file) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGoldenFonts);
  tearDownAll(() {
    final stale = staleKnownEntries(file, _registered, knownOverflows);
    if (stale.isNotEmpty) {
      fail('known_overflows.dart lists tests that $file does not define: ${stale.join(', ')}');
    }
  });
}

/// MASKS A REAL APP DEFECT. Delete this function when the theme is fixed.
///
/// AppTheme.from (lib/theme/app_theme.dart) sets fontFamily: 'Rubik' on the
/// base ThemeData, then replaces the text theme with seven styles that carry
/// no fontFamily and leaves the other eight slots null. In the shipping app
/// that means themed text falls through to the platform font and Rubik does
/// not render. This function forces Rubik onto all 15 slots so goldens show
/// real glyphs; without it they show Ahem blocks. It therefore makes the
/// goldens look better than the app is.
///
/// golden_harness_test.dart asserts the defect is still present. The day the
/// theme is fixed that test fails: delete this function, every call to it, and
/// that test, then regenerate the goldens.
ThemeData goldenTheme(ThemeData theme) =>
    theme.copyWith(textTheme: _withRubik(theme.textTheme));

TextTheme _withRubik(TextTheme t) {
  TextStyle rubik(TextStyle? s) => (s ?? const TextStyle()).copyWith(fontFamily: 'Rubik');
  return TextTheme(
    displayLarge: rubik(t.displayLarge),
    displayMedium: rubik(t.displayMedium),
    displaySmall: rubik(t.displaySmall),
    headlineLarge: rubik(t.headlineLarge),
    headlineMedium: rubik(t.headlineMedium),
    headlineSmall: rubik(t.headlineSmall),
    titleLarge: rubik(t.titleLarge),
    titleMedium: rubik(t.titleMedium),
    titleSmall: rubik(t.titleSmall),
    bodyLarge: rubik(t.bodyLarge),
    bodyMedium: rubik(t.bodyMedium),
    bodySmall: rubik(t.bodySmall),
    labelLarge: rubik(t.labelLarge),
    labelMedium: rubik(t.labelMedium),
    labelSmall: rubik(t.labelSmall),
  );
}

/// One overflow report: how far, which edge, the source line of the widget
/// that overflowed, and which render object it was (to tell one instance from
/// the same instance reported again on a later layout).
class Overflow {
  const Overflow(this.pixels, this.side, this.where, this.instance);

  final double pixels;
  final String side;
  final String where;
  final String instance;

  static final _size = RegExp(r'overflowed by ([\d.]+) pixels on the (\w+)');
  static final _source = RegExp(r'(?<=/)(?:lib|test)/[\w/]+\.dart:\d+');
  static final _instance = RegExp(r'Render\w+#[0-9a-f]+');

  static Overflow? tryParse(FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    final size = _size.firstMatch(text);
    if (size == null) return null;
    final full = '$text\n${details.toString(minLevel: DiagnosticLevel.debug)}';
    return Overflow(
      double.parse(size.group(1)!),
      size.group(2)!,
      _source.firstMatch(full)?.group(0) ?? 'unknown',
      _instance.firstMatch(full)?.group(0) ?? '',
    );
  }

  @override
  String toString() => '${pixels}px on the $side at $where';
}

/// A testWidgets that fails on any overflow the known list does not name.
///
/// Known overflows are expected to occur: if a listed one stops happening the
/// test fails too, so whoever fixes it also deletes the entry.
void goldenWidgets(String description, Future<void> Function(WidgetTester tester) body) {
  _registered.add(description);
  testWidgets(description, (tester) async {
    final seen = await captureOverflows(() => body(tester));
    final problems = overflowProblems(seen, knownOverflows[description]?.overflows ?? const []);
    if (problems.isNotEmpty) fail('$description\n${problems.join('\n')}');
  });
}

final _registered = <String>{};

/// Runs [body] with every overflow report diverted into the returned list,
/// one entry per distinct render object, instead of failing or printing.
/// Any other framework error still goes to the test binding.
Future<List<Overflow>> captureOverflows(Future<void> Function() body) async {
  final seen = <Overflow>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final overflow = Overflow.tryParse(details);
    if (overflow == null) {
      previous?.call(details);
    } else if (!seen.any((o) => _sameInstance(o, overflow))) {
      seen.add(overflow);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return seen;
}

bool _sameInstance(Overflow a, Overflow b) =>
    a.instance.isNotEmpty &&
    a.instance == b.instance &&
    a.side == b.side &&
    a.where == b.where &&
    (a.pixels - b.pixels).abs() <= _tolerance;

/// Within this the same overflow measured on another platform still matches.
const _tolerance = 0.5;

/// Compares what overflowed with what the known list says should. Each
/// expected entry must match exactly its listed count of overflows at the same
/// source line, edge and size; anything left over is unexpected. Empty means
/// the test agrees with the list.
List<String> overflowProblems(List<Overflow> seen, List<ExpectedOverflow> expected) {
  final remaining = [...seen];
  final problems = <String>[];
  for (final entry in expected) {
    final hits = remaining
        .where((o) =>
            o.where == entry.where &&
            o.side == entry.side &&
            (o.pixels - entry.pixels).abs() <= _tolerance)
        .toList();
    remaining.removeWhere(hits.contains);
    if (hits.length != entry.count) {
      problems.add('known_overflows.dart expects ${entry.count} overflow(s) of $entry but the '
          'test produced ${hits.length}. If a fix landed, delete or lower the entry.');
    }
  }
  for (final extra in remaining) {
    problems.add('Unexpected layout overflow, not in known_overflows.dart: $extra');
  }
  return problems;
}

/// Known-list tests of [file] that are not in [registered]: an entry naming a
/// test that no longer exists would otherwise sit in the list forever.
List<String> staleKnownEntries(
  String file,
  Set<String> registered,
  Map<String, KnownOverflow> known,
) =>
    [
      for (final e in known.entries)
        if (e.value.file == file && !registered.contains(e.key)) e.key,
    ];
