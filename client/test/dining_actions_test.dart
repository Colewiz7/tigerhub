/// The row actions on the Dining tab: pin, hide and move, end to end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/services/preferences.dart';

import 'support/context_menu_harness.dart';
import 'support/dining_harness.dart';

Finder _inSheet(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

void main() {
  setUpDining();

  testWidgets('Pin from the menu moves the place into Pinned', (tester) async {
    MenuProbe().install(tester);
    await pumpDiningScreen(tester);
    expect(find.text('Pinned'), findsNothing);
    await secondaryTap(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Pin');
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text("Gracie's"), findsOneWidget);
    expect(Preferences.instance.isPinned(21), isTrue);
  });

  testWidgets('Hide moves the place under Hidden and Unhide brings it back', (tester) async {
    MenuProbe().install(tester);
    await pumpDiningScreen(tester);
    await secondaryTap(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Hide');
    expect(find.text("Gracie's"), findsNothing);
    // Open now keeps hidden places out, All lists them
    expect(find.text('Hidden (1)'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden (1)'));
    await tester.pumpAndSettle();
    await secondaryTap(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Unhide');
    expect(find.text('Hidden (1)'), findsNothing);
    expect(find.text("Gracie's"), findsOneWidget);
  });

  testWidgets('Move to group puts the place in the chosen group', (tester) async {
    MenuProbe().install(tester);
    await pumpDiningScreen(tester);
    await longPress(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Move to group');
    expect(find.text('Move to group'), findsOneWidget);
    await tester.tap(_inSheet('Golisano'));
    await tester.pumpAndSettle();
    expect(find.text('Golisano'), findsOneWidget);
    expect(Preferences.instance.diningLayout.moved, {21: 'golisano'});
    // moving back to its own group leaves no diff
    await longPress(tester, find.text("Gracie's"));
    await tapMenuItem(tester, 'Move to group');
    await tester.tap(_inSheet('Dorm side'));
    await tester.pumpAndSettle();
    expect(Preferences.instance.diningLayout.isEmpty, isTrue);
  });
}
