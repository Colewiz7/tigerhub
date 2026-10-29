/// Settings > Campus: post office mode, Reset and Unhide all, each with Undo.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/campus_layout.dart';
import 'package:tigerhub/screens/settings/campus_section.dart';
import 'package:tigerhub/screens/settings/settings_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
    home: const Scaffold(body: CampusSection()),
  ));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String label) => tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData().flagsCollection.isEnabled == Tristate.isTrue;

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
  });
  tearDown(Preferences.instance.resetForTests);

  testWidgets('Settings lists Campus', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: SettingsScreen(
          scheme: SchemeController(),
          events: const Result(value: null, state: DataState.priming),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Campus'), findsOneWidget);
    await tester.tap(find.text('Campus'));
    await tester.pumpAndSettle();
    expect(find.text('Post offices'), findsOneWidget);
    expect(find.text('Unhide all'), findsOneWidget);
  });

  testWidgets('post offices default to my side and All flips the saved mode', (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();
    bool selected(String label) => tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData().flagsCollection.isSelected == Tristate.isTrue;
    expect(selected('My side'), isTrue);
    expect(selected('All'), isFalse);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(Preferences.instance.campusLayout.allOffices, isTrue);
    expect(selected('All'), isTrue);

    await tester.tap(find.text('My side'));
    await tester.pumpAndSettle();
    expect(Preferences.instance.campusLayout.isEmpty, isTrue);
    handle.dispose();
  });

  testWidgets('both buttons start off when there is nothing to reset', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(_enabled(tester, 'Reset Campus'), isFalse);
    expect(_enabled(tester, 'Unhide all'), isFalse);
    handle.dispose();
  });

  testWidgets('Reset Campus clears the layout and Undo brings it back', (tester) async {
    final prefs = Preferences.instance;
    await prefs.setCampusLayout(CampusLayout.empty.moveSection('shed', -1).hideSection('links').withAllOffices(true));
    await _pump(tester);
    await tester.tap(find.text('Reset Campus'));
    await tester.pumpAndSettle();
    expect(prefs.campusLayout.isEmpty, isTrue);
    expect(find.text('Campus reset'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.campusLayout.order.take(2), ['mail', 'find']);
    expect(prefs.campusLayout.hidden, {'links'});
    expect(prefs.campusLayout.allOffices, isTrue);
  });

  testWidgets('Unhide all brings back rows, offices and facilities, and Undo hides them again', (tester) async {
    final prefs = Preferences.instance;
    await prefs.setCampusLayout(CampusLayout.empty.hideSection('links').hideOffice('dsp').hideFacility('Pool').withAllOffices(true));
    await _pump(tester);
    await tester.tap(find.text('Unhide all'));
    await tester.pumpAndSettle();
    expect(prefs.campusLayout.hasHidden, isFalse);
    // the office choice is not a hidden row
    expect(prefs.campusLayout.allOffices, isTrue);
    expect(find.text('Rows unhidden'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.campusLayout.hidden, {'links'});
    expect(prefs.campusLayout.hiddenOffices, {'dsp'});
    expect(prefs.campusLayout.hiddenFacilities, {'Pool'});
  });

  testWidgets('Undo after Unhide all keeps edits made since', (tester) async {
    final prefs = Preferences.instance;
    await prefs.setCampusLayout(CampusLayout.empty.hideSection('links'));
    await _pump(tester);
    await tester.tap(find.text('Unhide all'));
    await tester.pumpAndSettle();
    await prefs.setCampusLayout(prefs.campusLayout.hideSection('shed'));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.campusLayout.hidden, {'links', 'shed'});
  });

  testWidgets('the controls are 48 point targets', (tester) async {
    await _pump(tester);
    for (final label in const ['My side', 'All', 'Reset Campus', 'Unhide all']) {
      expect(tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first).height, greaterThanOrEqualTo(48), reason: label);
    }
  });
}
