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

/// Call once from main() of any file that takes goldens.
void setUpGoldenFonts() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGoldenFonts);
}

/// The app theme with Rubik forced onto every text style.
///
/// AppTheme.from sets fontFamily on the base ThemeData and then replaces the
/// text theme with seven styles that carry no family and leave the other
/// eight slots null, so in the app today those styles fall through to the
/// platform font and Rubik never renders (see the A+B harness report). Without
/// this a golden shows Ahem blocks. Once the app theme carries the family
/// itself, this becomes a no-op and can be dropped.
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

/// One overflow report: how far, and the lib/ source line that built it.
class Overflow {
  const Overflow(this.pixels, this.where);

  final double pixels;
  final String where;

  static final _size = RegExp(r'overflowed by ([\d.]+) pixels');
  static final _source = RegExp(r'lib/[\w/]+\.dart:\d+');

  static Overflow? tryParse(FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    final size = _size.firstMatch(text);
    if (size == null) return null;
    final full = '$text\n${details.toString(minLevel: DiagnosticLevel.debug)}';
    return Overflow(
      double.parse(size.group(1)!),
      _source.firstMatch(full)?.group(0) ?? 'unknown',
    );
  }

  @override
  String toString() => '${pixels}px at $where';
}

/// A testWidgets that fails on any overflow the known list does not name.
///
/// Known overflows are expected to occur: if a listed one stops happening the
/// test fails too, so whoever fixes it also deletes the entry.
void goldenWidgets(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    final seen = <Overflow>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final overflow = Overflow.tryParse(details);
      if (overflow == null) {
        previous?.call(details);
      } else {
        seen.add(overflow);
      }
    };
    try {
      await body(tester);
    } finally {
      FlutterError.onError = previous;
    }
    _checkOverflows(description, seen);
  });
}

/// Within this the same overflow measured on another platform still matches.
const _tolerance = 0.5;

void _checkOverflows(String description, List<Overflow> seen) {
  final known = knownOverflows[description];
  final expected = known?.pixels ?? const <double>[];
  final unexpected = <Overflow>[];
  final matched = <double>{};
  for (final overflow in seen) {
    final hit = expected.where((px) => (px - overflow.pixels).abs() <= _tolerance);
    if (hit.isEmpty) {
      if (!unexpected.any((u) => u.pixels == overflow.pixels && u.where == overflow.where)) {
        unexpected.add(overflow);
      }
    } else {
      matched.add(hit.first);
    }
  }
  final missing = expected.where((px) => !matched.contains(px)).toList();
  final problems = [
    if (unexpected.isNotEmpty)
      'Unexpected layout overflow, not in known_overflows.dart: ${unexpected.join('; ')}',
    if (missing.isNotEmpty)
      'known_overflows.dart lists ${missing.join(', ')}px for "$description" but it no longer '
          'overflows by that. Fix landed? Delete the entry.',
  ];
  if (problems.isNotEmpty) fail(problems.join('\n'));
}
