/// The masthead wordmark.
///
/// The interesting failure here is silent. The wordmark SVG asks for
/// `font-family="Space Grotesk"`, and the app used to register that face as
/// `SpaceGrotesk` with no space. Those do not match, so the wordmark would
/// still render, just in whatever the default sans happens to be, and look
/// merely slightly off rather than broken.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/config.dart';
import 'package:tigerhub/widgets/wordmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app registers every font family the art asks for', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final families = RegExp(
      r'^\s*- family:\s*(.+)$',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m.group(1)!.trim()).toSet();

    final wanted = <String>{};
    for (final file
        in Directory('assets/generated')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.svg'))) {
      for (final match in RegExp(
        'font-family="([^"]*)"',
      ).allMatches(file.readAsStringSync())) {
        // Only the first choice matters; the rest are fallbacks.
        wanted.add(match.group(1)!.split(',').first.trim());
      }
    }

    for (final family in wanted) {
      expect(
        families,
        contains(family),
        reason:
            'SVG art asks for "$family" but pubspec does not register '
            'it, so it silently falls back to a default face',
      );
    }
  });

  test('the masthead reads outlined wordmarks, not text ones', () {
    // flutter_svg ignores a clipPath containing <text>, which let the stripes
    // escape the letterforms entirely. The flattened variants carry outlines.
    for (final name in ['tigerhub-wide-flat', 'tigerhub-compact-flat']) {
      final body = File('assets/generated/wordmark/$name.svg')
          .readAsStringSync();
      expect(
        body.contains('<text'),
        isFalse,
        reason: '$name still has live text, so its stripes will not clip',
      );
      expect(
        body,
        contains('clipPath'),
        reason: '$name lost its stripe clip in flattening',
      );
    }
  });

  test('the source wordmark uses broad horizontal markings', () {
    final body = File('assets/generated/wordmark/tigerhub-wide.svg')
        .readAsStringSync();
    final stripeGroup = RegExp(
      r'<g clip-path="url\(#tiger-word\)"[^>]*>(.*?)</g>',
      dotAll: true,
    ).firstMatch(body)!.group(1)!;
    final paths = RegExp(r'<path d="([^"]+)"').allMatches(stripeGroup);

    expect(paths.length, 3);
    for (final path in paths) {
      final numbers = RegExp(r'-?\d+(?:\.\d+)?')
          .allMatches(path.group(1)!)
          .map((m) => double.parse(m.group(0)!));
      final values = numbers.toList();
      final xs = [for (var i = 0; i < values.length; i += 2) values[i]];
      final ys = [for (var i = 1; i < values.length; i += 2) values[i]];
      final width =
          xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
      final height =
          ys.reduce((a, b) => a > b ? a : b) -
          ys.reduce((a, b) => a < b ? a : b);
      expect(
        width,
        greaterThan(height * 3),
        reason: 'each tiger marking should read horizontally',
      );
    }
  });

  test('the wordmark files the masthead reads all exist', () {
    for (final name in ['tigerhub-wide-flat', 'tigerhub-compact-flat']) {
      final file = File('assets/generated/wordmark/$name.svg');
      expect(file.existsSync(), isTrue, reason: '$name.svg is missing');
      expect(file.readAsStringSync(), startsWith('<svg'));
    }
  });

  testWidgets('picks the compact mark when the masthead is narrow', (
    tester,
  ) async {
    // The wide mark needs 230 logical pixels. In the masthead it shares a row
    // with the settings and palette buttons, so the window is not the space
    // it gets.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 190, child: Wordmark())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hub follows the theme instead of defaulting to black', (
    tester,
  ) async {
    // "Hub" is painted with fill="currentColor". flutter_svg defaults that to
    // black, and the masthead sits on a near-black surface, so getting this
    // wrong makes half the app's own name disappear while everything still
    // renders and nothing throws.
    const ink = Color(0xFFF2E4DA);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            surface: Color(0xFF16100D),
            onSurface: ink,
          ),
        ),
        home: const Scaffold(
          body: Center(child: SizedBox(width: 260, child: Wordmark())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = svg.bytesLoader as SvgAssetLoader;
    expect(
      loader.theme?.currentColor,
      ink,
      reason:
          'currentColor must come from the scheme, or Hub renders black '
          'on a near-black masthead',
    );
  });

  testWidgets('the wordmark names the app to a screen reader', (tester) async {
    // It is the app's name rendered as art, so it must not be silent.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 260, child: Wordmark())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(AppConfig.appName), findsWidgets);
    handle.dispose();
  });

  testWidgets('a live theme change invalidates the coloured SVG', (
    tester,
  ) async {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFF76902),
        brightness: brightness,
      ),
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: Center(child: SizedBox(width: 260, child: Wordmark())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final darkKey = tester.widget<SvgPicture>(find.byType(SvgPicture)).key;

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    final lightKey = tester.widget<SvgPicture>(find.byType(SvgPicture)).key;

    expect(lightKey, isNot(darkKey));
  });
}
