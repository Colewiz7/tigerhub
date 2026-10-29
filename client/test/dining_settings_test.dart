/// Settings: Reset groups and Unhide all.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/dining_layout.dart';
import 'package:tigerhub/screens/settings/dining_section.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'support/dining_harness.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
    home: const Scaffold(body: DiningSection()),
  ));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String label) => tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData().flagsCollection.isEnabled == Tristate.isTrue;

void main() {
  setUpDining();

  testWidgets('both buttons start off when there is nothing to reset', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.text('Reset groups'), findsOneWidget);
    expect(find.text('Unhide all'), findsOneWidget);
    expect(_enabled(tester, 'Reset groups'), isFalse);
    expect(_enabled(tester, 'Unhide all'), isFalse);
    handle.dispose();
  });

  testWidgets('Reset groups clears the layout and Undo brings it back', (tester) async {
    final prefs = Preferences.instance;
    await prefs.setDiningLayout(DiningLayout.empty.addCustom('Mine').rename('shed', 'Library', defaultName: 'SHED'));
    await _pump(tester);
    await tester.tap(find.text('Reset groups'));
    await tester.pumpAndSettle();
    expect(prefs.diningLayout.isEmpty, isTrue);
    expect(find.text('Groups reset'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.diningLayout.custom, {'custom-1': 'Mine'});
    expect(prefs.diningLayout.renamed, {'shed': 'Library'});
  });

  testWidgets('Unhide all shows every hidden place again and Undo hides them', (tester) async {
    final prefs = Preferences.instance;
    await prefs.toggleHidden(21);
    await prefs.toggleHidden(32);
    await _pump(tester);
    await tester.tap(find.text('Unhide all'));
    await tester.pumpAndSettle();
    expect(prefs.hiddenDining, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.hiddenDining, {'21', '32'});
  });
}
