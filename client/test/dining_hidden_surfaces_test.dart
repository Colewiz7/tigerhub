/// A hidden dining group leaves the Dining tab, Open now and Today.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'support/dining_harness.dart';

void main() {
  setUpDining();

  Future<void> hideDormSide() => Preferences.instance.setGroupHidden('dorm_side', true);

  testWidgets('the Dining tab drops the hidden places and counts them under Hidden', (tester) async {
    await hideDormSide();
    await pumpDiningScreen(tester);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text("Gracie's"), findsNothing);
    expect(find.text('Beanz'), findsNothing);
    expect(find.text('Crossroads'), findsOneWidget);
    expect(find.text('Hidden (2)'), findsOneWidget);
  });

  testWidgets('Hidden lists them under the group with one Show button', (tester) async {
    await hideDormSide();
    await pumpDiningScreen(tester);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden (2)'));
    await tester.pumpAndSettle();

    expect(find.text("Gracie's"), findsOneWidget);
    expect(find.text('Beanz'), findsOneWidget);
    expect(find.text('Show Dorm side'), findsOneWidget);

    await tester.tap(find.text('Show Dorm side'));
    await tester.pumpAndSettle();
    expect(Preferences.instance.hiddenDiningGroups, isEmpty);
    expect(find.text("Gracie's"), findsOneWidget);
    expect(find.textContaining('Hidden ('), findsNothing);
  });

  testWidgets('Corner Store stays in a hidden Dorm side', (tester) async {
    await hideDormSide();
    await pumpDiningScreen(tester, places: [place(21, "Gracie's"), place(27, 'Corner Store')]);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Corner Store'), findsOneWidget);
    expect(find.text("Gracie's"), findsNothing);
  });

  testWidgets('Open now does not default on a place that is hidden', (tester) async {
    await hideDormSide();
    // only a Dorm side place is open, so nothing visible is open
    await pumpDiningScreen(tester, places: [place(21, "Gracie's"), place(23, 'Crossroads', open: false)]);

    expect(find.text('All closed'), findsNothing);
    expect(find.text('Crossroads'), findsOneWidget);
  });

  testWidgets('Favorites leaves out a pinned place in a hidden group', (tester) async {
    await Preferences.instance.togglePinned(21);
    await Preferences.instance.togglePinned(23);
    await hideDormSide();
    await pumpDiningScreen(tester);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();

    expect(find.text('Crossroads'), findsOneWidget);
    expect(find.text("Gracie's"), findsNothing);
    // the pin is still stored
    expect(Preferences.instance.pinnedDining, contains('21'));
  });

  testWidgets('the Today card drops them too', (tester) async {
    await hideDormSide();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiningCard(
            result: Result(value: Collection(data: sampleDining, stale: false), state: DataState.ok),
            onShowAll: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Gracie's"), findsNothing);
    expect(find.text('Crossroads'), findsOneWidget);
  });
}
