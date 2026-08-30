import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/campus_map.dart';

const west = CampusMapFeature(
  id: 1,
  kind: 'water',
  kindName: 'Water fountains',
  name: 'West fountain',
  geometryType: 'Point',
  coordinates: [
    [GeoCoordinate(-77.68, 43.08)],
  ],
  building: 'GOL',
  floor: '1st floor',
);

const east = CampusMapFeature(
  id: 2,
  kind: 'aed',
  kindName: 'Defibrillators',
  name: 'East AED',
  geometryType: 'Point',
  coordinates: [
    [GeoCoordinate(-77.67, 43.09)],
  ],
  building: 'SHED',
  note: 'Near the main entrance',
);

Widget app({bool priming = false, List<CampusEvent> events = const []}) =>
    MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFF76902),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: CampusMapView(
            result: Result(
              value: priming
                  ? null
                  : const Collection(data: [west, east], stale: false),
              state: priming ? DataState.priming : DataState.ok,
            ),
            events: Result(
              value: Collection(data: events, stale: false),
              state: DataState.ok,
            ),
          ),
        ),
      ),
    );

void main() {
  test('projection keeps longitude on X and north toward the top', () {
    final projection = CampusMapProjection(const [
      west,
      east,
    ], const Size(800, 500));
    final westPoint = projection.project(west.anchor!);
    final eastPoint = projection.project(east.anchor!);

    expect(eastPoint.dx, greaterThan(westPoint.dx));
    expect(eastPoint.dy, lessThan(westPoint.dy));
    expect(projection.nearest(westPoint)?.id, west.id);
  });

  testWidgets('map exposes filters, fit control, and list equivalent', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Water fountains'), findsOneWidget);
    expect(find.text('Defibrillators'), findsOneWidget);
    expect(find.byTooltip('Fit campus'), findsOneWidget);
    expect(find.text('West fountain'), findsOneWidget);
    expect(find.text('East AED'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('selecting the list shows useful place details', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('East AED'));
    await tester.pump();

    expect(find.text('SHED'), findsOneWidget);
    expect(find.text('Near the main entrance'), findsOneWidget);
    expect(find.byTooltip('Close details'), findsOneWidget);
  });

  testWidgets('priming uses the shared skeleton', (tester) async {
    await tester.pumpWidget(app(priming: true));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading campus map'), findsOneWidget);
  });

  testWidgets('events mode reports mapped and unmapped events', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await tester.pumpWidget(
      app(
        events: [
          CampusEvent(
            uid: 'mapped',
            source: 'test',
            title: 'SHED workshop',
            startsAt: today,
            location: 'SHED 1300',
          ),
          CampusEvent(
            uid: 'unmapped',
            source: 'test',
            title: 'Mystery event',
            startsAt: today,
            location: 'Unknown Hall',
          ),
        ],
      ),
    );

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();

    expect(find.text('1 mapped · 1 without a location'), findsOneWidget);
    expect(find.text('SHED workshop'), findsOneWidget);
    expect(find.text('Mystery event'), findsNothing);
  });
}
