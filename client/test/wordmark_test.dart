/// The masthead wordmark.
///
/// The interesting failure here is silent. Codex's SVG asks for
/// `font-family="Space Grotesk"`, and the app used to register that face as
/// `SpaceGrotesk` with no space. Those do not match, so the wordmark would
/// still render, just in whatever the default sans happens to be, and look
/// merely slightly off rather than broken.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/config.dart';
import 'package:tigerhub/widgets/wordmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app registers every font family the art asks for', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final families = RegExp(r'^\s*- family:\s*(.+)$', multiLine: true)
        .allMatches(pubspec)
        .map((m) => m.group(1)!.trim())
        .toSet();

    final wanted = <String>{};
    for (final file in Directory('assets/generated')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))) {
      for (final match in RegExp('font-family="([^"]*)"')
          .allMatches(file.readAsStringSync())) {
        // Only the first choice matters; the rest are fallbacks.
        wanted.add(match.group(1)!.split(',').first.trim());
      }
    }

    for (final family in wanted) {
      expect(families, contains(family),
          reason: 'SVG art asks for "$family" but pubspec does not register '
              'it, so it silently falls back to a default face');
    }
  });

  test('the wordmark files the masthead reads all exist', () {
    for (final name in ['tigerhub-wide', 'tigerhub-compact']) {
      final file = File('assets/generated/wordmark/$name.svg');
      expect(file.existsSync(), isTrue, reason: '$name.svg is missing');
      expect(file.readAsStringSync(), startsWith('<svg'));
    }
  });

  testWidgets('picks the compact mark when the masthead is narrow',
      (tester) async {
    // The wide mark needs 230 logical pixels. In the masthead it shares a row
    // with the settings and palette buttons, so the window is not the space
    // it gets.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 190, child: Wordmark())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wordmark names the app to a screen reader', (tester) async {
    // It is the app's name rendered as art, so it must not be silent.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 260, child: Wordmark())),
      ),
    ));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(AppConfig.appName), findsWidgets);
    handle.dispose();
  });
}
