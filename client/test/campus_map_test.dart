import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';
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
  test('every place category has its own map symbol', () {
    const kinds = [
      'water',
      'ev_charge',
      'blue_light',
      'aed',
      'restroom_all_gender',
      'restroom_accessible',
      'atm',
      'changing_table',
      'entrance_accessible',
      'bus_stop',
      'bike_rack',
      'reload',
    ];

    expect(kinds.map(mapPlaceIcon).toSet(), hasLength(kinds.length));
  });

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
    // angles between them were wrong. Equal distances on the ground must come
    // out as equal distances in pixels, whatever shape the window is.
    for (final size in [
      const Size(1200, 600),
      const Size(600, 900),
      const Size(800, 800),
    ]) {
      final projection = CampusMapProjection(const [
        CampusMapFeature(
          id: 1,
          kind: '_campus',
          kindName: 'Academic Building',
          name: 'Block',
          geometryType: 'Polygon',
          coordinates: [
            [
              GeoCoordinate(-77.68, 43.08),
              GeoCoordinate(-77.66, 43.08),
              GeoCoordinate(-77.66, 43.0946),
              GeoCoordinate(-77.68, 43.0946),
            ],
          ],
        ),
      ], size);

      // A degree of longitude is cos(latitude) as long as a degree of
      // latitude, so these two steps cover the same ground distance.
      final from = projection.project(const GeoCoordinate(-77.68, 43.08));
      final acrossX =
          (projection.project(const GeoCoordinate(-77.66, 43.08)).dx - from.dx)
              .abs();
      final acrossY =
          (projection.project(const GeoCoordinate(-77.68, 43.0946)).dy -
                  from.dy)
              .abs();

      expect(
        acrossX,
        closeTo(acrossY, acrossY * 0.02),
        reason: 'equal ground distances must project equally at $size',
      );
    }
  });

  group('zooming reveals more, rather than magnifying the same thing', () {
    test('the scale bar measures a shorter distance as you zoom in', () {
      // The bar is held at a fifth of the screen, so zooming in has to pick a
      // smaller round number rather than run the bar off the edge.
      expect(scaleBarMetres(500), 500);
      expect(scaleBarMetres(120), 200);
      expect(scaleBarMetres(30), 50);
      expect(scaleBarMetres(8), 10);
    });

    test('it never picks a distance smaller than what has to fit', () {
      for (final target in [7.0, 45.0, 99.0, 260.0, 900.0]) {
        expect(
          scaleBarMetres(target),
          greaterThanOrEqualTo(target),
          reason: 'a bar labelled less than it spans would be wrong',
        );
      }
    });

    test('the painter redraws when the zoom changes', () {
      // Without this the canvas is painted once in unzoomed coordinates and
      // the viewer just scales the result, so labels grow with the buildings
      // and no new ones ever appear.
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
      CampusMapPainter at(double zoom) => CampusMapPainter(
        features: const [west, east],
        selectedId: null,
        scheme: scheme,
        zoom: zoom,
      );

      expect(at(2).shouldRepaint(at(1)), isTrue);
      expect(at(1).shouldRepaint(at(1)), isFalse);
    });

    test('the map repaints once the walking network finishes loading', () {
      // The asset decodes after the first frame, so without this the paths
      // would not appear until something else happened to trigger a repaint.
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
      CampusMapPainter withPaths(CampusPaths paths) => CampusMapPainter(
        features: const [west, east],
        selectedId: null,
        scheme: scheme,
        paths: paths,
      );

      final loaded = CampusPaths(
        foot: const [
          [GeoCoordinate(-77.68, 43.08), GeoCoordinate(-77.67, 43.085)],
        ],
        road: const [],
      );
      expect(
        withPaths(loaded).shouldRepaint(withPaths(const CampusPaths.empty())),
        isTrue,
      );
    });
  });

  group('the projection is reused, but only while it is still valid', () {
    // Building one measured 7.27ms of a 13.9ms paint, so it is cached. A cache
    // that held on too long would silently project into a stale rect, which is
    // far worse than the cost it saves.
    setUp(CampusMapProjection.resetCacheForTest);

    test('identical inputs reuse the same projection', () {
      const size = Size(900, 500);
      expect(
        identical(
          CampusMapProjection(const [west, east], size),
          CampusMapProjection(const [west, east], size),
        ),
        isTrue,
      );
    });

    test('a resized window rebuilds it', () {
      final a = CampusMapProjection(const [west, east], const Size(900, 500));
      final b = CampusMapProjection(const [west, east], const Size(500, 900));
      expect(identical(a, b), isFalse);
      expect(a.mapRect, isNot(b.mapRect));
    });

    test('a changed feature list rebuilds it', () {
      final a = CampusMapProjection(const [west, east], const Size(900, 500));
      final b = CampusMapProjection(
        const [west, east, remote],
        const Size(900, 500),
      );
      expect(identical(a, b), isFalse);
    });

    test('a changed bounds list rebuilds it', () {
      const size = Size(900, 500);
      final a = CampusMapProjection(const [west, east], size);
      final b = CampusMapProjection(
        const [west, east],
        size,
        boundsFeatures: const [west],
      );
      expect(identical(a, b), isFalse);
    });
  });

  test('the map fills the panel it is given', () {
    // Being isotropic is not enough on its own. Fitting the campus into a wide
    // panel used 60% of it and stranded 357px of dead width, which is why the
    // bounds grow to the window shape rather than the drawing being stretched.
    const size = Size(970, 553);
    final projection = CampusMapProjection(const [west, east], size);
    final rect = projection.mapRect;

    expect(rect.width, closeTo(size.width - 68, 1));
    expect(rect.height, closeTo(size.height - 68, 1));
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
    expect(find.byIcon(Icons.water_drop_rounded), findsWidgets);
    expect(find.byIcon(Icons.health_and_safety_rounded), findsWidgets);
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

  test('painted pins announce and activate their place', () {
    CampusMapFeature? selected;
    final painter = CampusMapPainter(
      features: const [west, east],
      selectedId: null,
      scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      onSelect: (feature) => selected = feature,
    );

    final pins = painter.semanticsBuilder(const Size(800, 500));
    final westPin = pins.singleWhere(
      (pin) => pin.properties.label == 'Water fountains, West fountain, GOL',
    );
    expect(westPin.properties.button, isTrue);
    expect(westPin.properties.onTap, isNotNull);

    westPin.properties.onTap!();
    expect(selected, west);
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
