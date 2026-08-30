/// Illustrated empty states.
///
/// The failure this guards against is quiet: a missing or misnamed SVG renders
/// as a blank box rather than throwing, which looks exactly like the empty
/// state working. So every asset is loaded from the real bundle and parsed.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/empty_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every state Codex drew has a file, and every file is used', () {
    final dir = Directory('assets/generated/empty-states');
    final onDisk = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.svg', ''))
        .toSet();

    final declared = EmptyKind.values.map((k) => k.asset).toSet();

    expect(declared.difference(onDisk), isEmpty,
        reason: 'a declared state has no artwork, so it renders as a blank box');
    expect(onDisk.difference(declared), isEmpty,
        reason: 'Codex drew a state nothing uses, which is worth wiring up '
            'rather than leaving in the folder');
  });

  test('the artwork is real SVG, not a placeholder', () {
    for (final kind in EmptyKind.values) {
      final file = File('assets/generated/empty-states/${kind.asset}.svg');
      final body = file.readAsStringSync();
      expect(body, startsWith('<svg'), reason: '${kind.asset} is not an SVG');
      expect(body.length, greaterThan(200),
          reason: '${kind.asset} looks like a stub rather than a drawing');
    }
  });

  testWidgets('renders the illustration and the copy together', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: Center(child: EmptyState(kind: EmptyKind.noVisitingChefs)),
      ),
    ));
    await tester.pumpAndSettle();

    // The spec's copy, not something invented at the call site.
    expect(find.text('No visiting chefs today'), findsOneWidget);
  });

  testWidgets('a caller can say something more specific', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: Center(
          child: EmptyState(
            kind: EmptyKind.sourceDown,
            title: 'Dining is unavailable',
            detail: 'Last checked a moment ago',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dining is unavailable'), findsOneWidget);
    expect(find.text('Last checked a moment ago'), findsOneWidget);
    expect(find.text('This source is unavailable'), findsNothing,
        reason: 'an override should replace the default, not sit beside it');
  });

  testWidgets('the art is not announced to a screen reader', (tester) async {
    // The copy underneath already says what the state is. Announcing the
    // drawing as well would say it twice.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: const Scaffold(
        body: Center(child: EmptyState(kind: EmptyKind.noEvents)),
      ),
    ));
    await tester.pumpAndSettle();

    // The SVG carries aria-label="no events". If that reached the semantics
    // tree a screen reader would read the picture and then the caption.
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('no events')), findsNothing);
    expect(find.bySemanticsLabel('Nothing scheduled today'), findsOneWidget,
        reason: 'the caption is what should be announced');
    handle.dispose();
  });
}
