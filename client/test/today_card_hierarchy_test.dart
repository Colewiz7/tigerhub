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

  testWidgets('empty chefs content is centered in its dashboard card', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 560,
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

    final card = find
        .descendant(
          of: find.byType(VisitingChefsCard),
          matching: find.byType(Material),
        )
        .first;
    final mark = find.byIcon(Icons.room_service_rounded);
    final body = find
        .ancestor(
          of: find.text('No visiting chefs today'),
          matching: find.byType(Center),
        )
        .first;
    expect(
      (tester.getCenter(mark).dx - tester.getCenter(card).dx).abs(),
      lessThan(1),
    );
    expect(
      (tester.getCenter(find.text('No visiting chefs today')).dx -
              tester.getCenter(card).dx)
          .abs(),
      lessThan(1),
    );
    final contentCenterY =
        (tester.getTopLeft(mark).dy +
            tester.getBottomRight(find.text('No visiting chefs today')).dy) /
        2;
    expect((contentCenterY - tester.getCenter(body).dy).abs(), lessThan(8));
    expect((contentCenterY - tester.getCenter(card).dy).abs(), lessThan(50));
  });
}
