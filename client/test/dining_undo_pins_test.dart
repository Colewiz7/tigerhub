/// Undo of Hide and of Unhide all keeps pins, and a pinned row keeps its own icon.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/screens/settings/dining_section.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';

import 'support/context_menu_harness.dart';
import 'support/dining_harness.dart';

void main() {
  setUpDining();

  testWidgets('Hide a pinned place, Undo, and it is pinned again', (tester) async {
    MenuProbe().install(tester);
    final prefs = Preferences.instance;
    await prefs.togglePinned(21);
    await pumpDiningScreen(tester);
    await secondaryTap(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Hide');
    expect(prefs.isHidden(21), isTrue);
    expect(prefs.isPinned(21), isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.isHidden(21), isFalse);
    expect(prefs.isPinned(21), isTrue);
  });

  testWidgets('Hide an unpinned place, Undo, and it stays unpinned', (tester) async {
    MenuProbe().install(tester);
    final prefs = Preferences.instance;
    await pumpDiningScreen(tester);
    await secondaryTap(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Hide');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.isHidden(21), isFalse);
    expect(prefs.isPinned(21), isFalse);
  });

  testWidgets('Unhide all, pin another, Undo, and the pin is intact', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    final prefs = Preferences.instance;
    await prefs.togglePinned(21);
    await prefs.toggleHidden(32);
    await prefs.togglePinned(31);
    await prefs.toggleHidden(31);
    expect(prefs.pinnedDining, {'21'});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: const Scaffold(body: DiningSection()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unhide all'));
    await tester.pumpAndSettle();
    await prefs.togglePinned(24);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.hiddenDining, {'32', '31'});
    expect(prefs.pinnedDining, {'21', '24'});
  });

  testWidgets('a pinned row keeps the place icon and says Pinned', (tester) async {
    final prefs = Preferences.instance;
    await prefs.togglePinned(21);
    final location = place(21, "Gracie's");
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(body: DiningRow(location: location)),
    ));
    final icons = tester.widgetList<Icon>(find.byType(Icon)).map((i) => i.icon).toList();
    expect(icons, contains(AppIconKind.diningHall.material));
    expect(icons, isNot(contains(AppIconKind.pinned.material)));
    expect(find.textContaining('Pinned · '), findsOneWidget);
    await prefs.togglePinned(21);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DiningRow(location: location))));
    expect(find.textContaining('Pinned'), findsNothing);
  });
}
