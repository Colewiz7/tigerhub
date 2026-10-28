/// Edit mode: reorder, rename, create and delete groups, and the Move button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/dining_layout.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/services/preferences.dart';

import 'support/context_menu_harness.dart';
import 'support/dining_harness.dart';

Future<void> _edit(WidgetTester tester) async {
  await pumpDiningScreen(tester);
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit groups'));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

final _dialogField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

Finder _in(Finder scope, Finder target) => find.descendant(of: scope, matching: target);

// the header row of one group
Finder _header(String name) => find.ancestor(of: find.text(name), matching: find.byType(Semantics)).first;

void main() {
  setUpDining();
  final defaults = [
    (id: 'a', name: 'Alpha'),
    (id: 'b', name: 'Beta'),
    (id: 'other', name: 'Other'),
  ];

  group('moveGroup', () {
    test('swaps with the neighbour and stores a diff', () {
      final layout = DiningLayout.empty.moveGroup('b', -1, defaults);
      expect(layout.groupOrder(defaults), ['b', 'a', 'other']);
      expect(layout.moveGroup('b', 1, defaults).isEmpty, isTrue);
    });

    test('Other never moves and nothing swaps with it', () {
      expect(DiningLayout.empty.moveGroup('other', -1, defaults).isEmpty, isTrue);
      expect(DiningLayout.empty.moveGroup('b', 1, defaults).isEmpty, isTrue);
      expect(DiningLayout.empty.moveGroup('a', -1, defaults).isEmpty, isTrue);
    });
  });

  testWidgets('edit mode turns the long-press menu off and shows a Move button', (tester) async {
    MenuProbe().install(tester);
    await _edit(tester);
    expect(find.byTooltip('Move to group'), findsWidgets);
    await tester.longPress(find.text("Gracie's"));
    await tester.pumpAndSettle();
    expect(find.text('Hide'), findsNothing);
  });

  testWidgets('Done leaves edit mode and the Move buttons go', (tester) async {
    await _edit(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Move to group'), findsNothing);
    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets('Move down swaps a default group with the next one', (tester) async {
    await _edit(tester);
    expect(_y(tester, 'Dorm side'), lessThan(_y(tester, 'SHED')));
    await tester.tap(_in(_header('Dorm side'), find.byTooltip('Move down')));
    await tester.pumpAndSettle();
    expect(_y(tester, 'SHED'), lessThan(_y(tester, 'Dorm side')));
    expect(Preferences.instance.diningLayout.order.first, 'shed');
  });

  testWidgets('the first group cannot move up and Other cannot move at all', (tester) async {
    await _edit(tester);
    final up = tester.widget<IconButton>(find.ancestor(of: _in(_header('Dorm side'), find.byTooltip('Move up')), matching: find.byType(IconButton)).first);
    expect(up.onPressed, isNull);
    expect(_in(_header('Other'), find.byTooltip('Move up')), findsOneWidget);
    for (final tip in ['Move up', 'Move down']) {
      final button = tester.widget<IconButton>(find.ancestor(of: _in(_header('Other'), find.byTooltip(tip)), matching: find.byType(IconButton)).first);
      expect(button.onPressed, isNull, reason: tip);
    }
  });

  testWidgets('screen reader gets Move up and Move down on the header', (tester) async {
    final handle = tester.ensureSemantics();
    await _edit(tester);
    final node = tester.getSemantics(_header('SHED'));
    final labels = [for (final id in node.getSemanticsData().customSemanticsActionIds!) CustomSemanticsAction.getAction(id)!.label];
    expect(labels, unorderedEquals(['Move up', 'Move down', 'Rename']));
    handle.dispose();
  });

  testWidgets('a default group renames but has no Delete', (tester) async {
    await _edit(tester);
    expect(find.byTooltip('Delete group'), findsNothing);
    await tester.tap(_in(_header('SHED'), find.byTooltip('Rename')));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField, 'Library side');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Library side'), findsOneWidget);
    expect(find.text('SHED'), findsNothing);
    expect(Preferences.instance.diningLayout.renamed, {'shed': 'Library side'});
  });

  testWidgets('own groups are created, filled, and deleted with Undo', (tester) async {
    await _edit(tester);
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField, 'Study snacks');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Study snacks'), findsOneWidget);
    // before Other
    expect(_y(tester, 'Study snacks'), lessThan(_y(tester, 'Other')));
    expect(find.byTooltip('Delete group'), findsOneWidget);

    // a place moves in through its Move button
    await tester.tap(find.descendant(of: find.ancestor(of: find.text("Gracie's"), matching: find.byType(InkWell)).first, matching: find.byTooltip('Move to group')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Study snacks')));
    await tester.pumpAndSettle();
    expect(Preferences.instance.diningLayout.moved, {21: 'custom-1'});

    await tester.tap(find.byTooltip('Delete group'));
    await tester.pumpAndSettle();
    expect(find.text('Study snacks'), findsNothing);
    // its place went home
    expect(Preferences.instance.diningLayout.moved, isEmpty);
    expect(find.text('Deleted Study snacks'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Study snacks'), findsOneWidget);
    expect(StaticConfig.instance.diningGroups.length, 7);
  });

  testWidgets('an empty Other has no header in edit mode', (tester) async {
    await pumpDiningScreen(tester, places: [place(21, "Gracie's")]);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit groups'));
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsNothing);
    expect(find.text('SHED'), findsOneWidget);
  });
}
