import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const remote = CampusMapFeature(
  id: 3,
  kind: 'aed',
  kindName: 'Defibrillators',
  name: 'Downtown AED',
  geometryType: 'Point',
  coordinates: [
    [GeoCoordinate(-77.50, 43.14)],
  ],
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

  test('the projection does not stretch one axis against the other', () {
    // It used to force a minimum 2.35:1 aspect so a wide window looked full.
    // The campus inside the bounds is 2342m by 2085m, so that stretched
    // longitude by 2.09x: buildings came out twice as wide as they are and the
    // angles between them were wrong. A square patch of ground must project to
    // a square patch of pixels.
    const size = Size(1200, 600);
    final projection = CampusMapProjection(
      const [
        CampusMapFeature(
          id: 1,
          kind: '_campus',
          kindName: 'Academic Building',
          name: 'Square block',
          geometryType: 'Polygon',
          coordinates: [
            [
              // Sized so the ground covered is square: a degree of longitude
              // is cos(latitude) as long as a degree of latitude.
              GeoCoordinate(-77.68, 43.08),
              GeoCoordinate(-77.66, 43.08),
              GeoCoordinate(-77.66, 43.0946),
              GeoCoordinate(-77.68, 43.0946),
            ],
          ],
        ),
      ],
      size,
    );

    final rect = projection.mapRect;
    expect(
      rect.width / rect.height,
      closeTo(1.0, 0.02),
      reason: 'square ground must not render as a wide rectangle',
    );
  });

  test('initial fit ignores remote places without deleting them', () {
    final projection = CampusMapProjection(const [
      west,
      east,
      remote,
    ], const Size(800, 500));

    expect(projection.maxLongitude, lessThan(-77.60));
    expect(
      projection.nearest(projection.project(remote.anchor!))?.id,
      remote.id,
    );
  });

  testWidgets('map exposes filters, fit control, and list equivalent', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.text('All places'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter map places'));
    await tester.pumpAndSettle();
    expect(find.text('Water fountains'), findsOneWidget);
    expect(find.text('Defibrillators'), findsOneWidget);
    expect(find.byTooltip('Fit campus'), findsOneWidget);
    expect(find.text('West fountain'), findsOneWidget);
    expect(find.text('East AED'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('the legend names what the outlines mean', (tester) async {
    // Without it the map asks you to infer that a hollow shape is a car park
    // and an olive one is grass.
    await tester.pumpWidget(app());

    expect(find.text('Building'), findsOneWidget);
    expect(find.text('Parking'), findsOneWidget);
    expect(find.text('Green space'), findsOneWidget);
  });

  test('each family is painted differently from the others', () {
    // The legend is only truthful if the three treatments actually differ.
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
    final built = mapFamilyPaints(MapFamily.built, scheme);
    final parking = mapFamilyPaints(MapFamily.parking, scheme);
    final open = mapFamilyPaints(MapFamily.open, scheme);

    expect(built.fill, isNotNull, reason: 'a building is a solid');
    expect(parking.fill, isNull, reason: 'a lot is hollow, not a building');
    expect(open.edge, isNull, reason: 'ground has no walls');
    expect(open.fill!.color, isNot(built.fill!.color));
    expect(parking.edge!.color, isNot(built.edge!.color));
  });

  testWidgets('double click and keyboard controls zoom the map', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.5, 0.01));

    final mapFocus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Focus && widget.focusNode?.debugLabel == 'Campus map',
      ),
    );
    mapFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.25, 0.01));

    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.5, 0.01));
    await tester.pump(const Duration(milliseconds: 400));
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
