import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';

void main() {
  testWidgets('visiting chefs card has one honest card-level count', (
    tester,
  ) async {
    const chefs = [
      MenuItem(id: 1, name: 'Chef One', locationName: 'Brick City Cafe'),
      MenuItem(id: 2, name: 'Chef Two', locationName: 'Crossroads'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 520,
            child: VisitingChefsCard(
              result: Result(
                value: Collection(data: chefs, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ScallopedBadge), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('CHEFS TODAY'), findsOneWidget);
  });

  testWidgets('the chefs card fills the box it is given', (tester) async {
    // It used to cap itself at one row on a compact card, which stranded a
    // single chef at the top with the rest of the card empty beneath. The card
    // is already given a shorter box for compact; BoundedList measures that box
    // and is the only thing that should decide the row count.
    const chefs = [
      MenuItem(id: 1, name: 'Chef One', locationName: 'Brick City Cafe'),
      MenuItem(id: 2, name: 'Chef Two', locationName: 'Crossroads'),
      MenuItem(id: 3, name: 'Chef Three', locationName: 'Gracie\'s'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 520,
            child: VisitingChefsCard(
              result: Result(
                value: Collection(data: chefs, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );

    for (final name in ['Chef One', 'Chef Two', 'Chef Three']) {
      expect(find.text(name), findsOneWidget, reason: '$name should fit');
    }
  });

  testWidgets('no visiting chefs keeps the illustrated empty state primary', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 520,
            child: VisitingChefsCard(
              result: Result(
                value: Collection<MenuItem>(data: [], stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ScallopedBadge), findsNothing);
    expect(find.text('No visiting chefs today'), findsOneWidget);
  });
}
