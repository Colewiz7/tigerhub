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
