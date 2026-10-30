import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_paths.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/frame_monitor.dart';
import 'package:tigerhub/services/frame_stats.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/segmented_picker.dart';

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

Widget app({bool priming = false, List<CampusEvent> events = const [], double width = 800}) =>
    MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFF76902),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: SizedBox(
          width: width,
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

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(kinds.map((kind) => mapPlaceIcon(kind).on(platform)).toSet(), hasLength(kinds.length));
    }
  });

  test('an AED pin is a heart monitor, not a safety shield', () {
    expect(mapPlaceIcon('aed'), AppIconKind.aed);
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
      final b = CampusMapProjection(const [
        west,
        east,
        remote,
      ], const Size(900, 500));
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

  testWidgets('map exposes filters, search, and list equivalent', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.text('All places'), findsOneWidget);
    expect(find.text('Water fountains'), findsOneWidget);
    expect(find.text('Defibrillators'), findsOneWidget);
    expect(find.text('West fountain'), findsNothing);
    expect(find.text('East AED'), findsNothing);

    await tester.tap(find.text('Water fountains'));
    await tester.pumpAndSettle();
    expect(find.text('West fountain'), findsOneWidget);
    expect(find.text('East AED'), findsNothing);
    expect(find.byIcon(Icons.water_drop_rounded), findsWidgets);

    await tester.tap(find.byTooltip('Filter map places'));
    await tester.pumpAndSettle();
    expect(find.text('Water fountains'), findsWidgets);
    expect(find.text('Defibrillators'), findsOneWidget);
    expect(find.byTooltip('Fit campus'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('the search button sits right of the filter, fit is gone', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final filter = tester.getRect(find.byTooltip('Filter map places'));
    final search = find.byTooltip('Search campus places (Ctrl+F)');

    expect(search, findsOneWidget);
    expect(find.byTooltip('Fit campus'), findsNothing);
    expect(tester.getRect(search).left, greaterThanOrEqualTo(filter.right));
    expect(
      tester.getSize(
        find.ancestor(of: search, matching: find.byType(IconButton)),
      ),
      const Size(48, 48),
    );

    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).autofocus,
      isFalse,
    );
  });

  testWidgets('zooming back out to 1x frames the whole campus again', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    controller.value = controller.value.clone()..translateByDouble(-30, -20, 0, 1);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();

    expect(controller.value, Matrix4.identity());
  });

  for (final width in const [390.0, 440.0]) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets('toolbar fits at ${width.toInt()} wide, ${textScale}x text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(textScale),
            ),
            child: app(width: width),
          ),
        );

        final filter = tester.getRect(find.byTooltip('Filter map places'));
        final search = tester.getRect(
          find.ancestor(
            of: find.byTooltip('Search campus places (Ctrl+F)'),
            matching: find.byType(IconButton),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(search.left, greaterThanOrEqualTo(filter.right));
        expect(search.right, lessThanOrEqualTo(width));
        expect(search.shortestSide, greaterThanOrEqualTo(48));
      });
    }
  }

  testWidgets('the legend names what the outlines mean', (tester) async {
    // Without it the map asks you to infer that a hollow shape is a car park
    // and an olive one is grass.
    await tester.pumpWidget(app());

    // the project notes 4: colour is never the only carrier. The building categories
    // are told apart by hue, so every family the map paints has to be named
    // where the reader can see it, and the legend is that place.
    for (final family in MapFamily.values) {
      expect(find.text(family.label), findsOneWidget, reason: family.name);
    }
  });

  test('each family is painted differently from the others', () {
    // The legend is only truthful if the three treatments actually differ.
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
    final built = mapFamilyPaints(MapFamily.residential, scheme);
    final parking = mapFamilyPaints(MapFamily.parking, scheme);
    final open = mapFamilyPaints(MapFamily.open, scheme);

    expect(built.fill, isNotNull, reason: 'a building is a solid');
    expect(
      parking.fill!.color,
      isNot(built.fill!.color),
      reason: 'a lot has its own faint token, not a building tint',
    );
    expect(open.edge, isNull, reason: 'ground has no walls');
    expect(open.fill!.color, isNot(built.fill!.color));
    expect(parking.edge!.color, isNot(built.edge!.color));
  });

  testWidgets('pan and zoom count in the Map scroll bucket', (tester) async {
    final monitor = FrameMonitor.instance;
    monitor.stats.reset();
    void frameNow() => monitor.stats
        .recordFrame(atUs: monitor.nowUs, buildUs: 1000, rasterUs: 1000);

    await tester.pumpWidget(app());
    final g = await tester.startGesture(tester.getCenter(find.byType(InteractiveViewer)));
    await g.moveBy(const Offset(40, 20));
    await tester.pump();
    frameNow();
    expect(monitor.stats.scrollSummary(frameTabMap).frames, 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(monitor.stats.tabSwitchSummary(frameTabMap).frames, 0);
    // The window is closed: a frame a moment later is not counted.
    monitor.stats
        .recordFrame(atUs: monitor.nowUs + 1000, buildUs: 1000, rasterUs: 1000);
    expect(monitor.stats.scrollSummary(frameTabMap).frames, 1);

    // Leaving the map mid gesture does not leave a window open.
    final g2 = await tester.startGesture(tester.getCenter(find.byType(InteractiveViewer)));
    await g2.moveBy(const Offset(40, 20));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    monitor.stats
        .recordFrame(atUs: monitor.nowUs + 1000000, buildUs: 1000, rasterUs: 1000);
    expect(monitor.stats.scrollSummary(frameTabMap).frames, 1);
    monitor.stats.reset();
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
    expect(find.text('1.5×'), findsOneWidget);

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
    expect(find.text('2.3×'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.5, 0.01));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('zoom controls reach 20x and stop there', (tester) async {
    await tester.pumpWidget(app());
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;

    expect(viewer.maxScale, 20);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.remove_rounded),
          )
          .onPressed,
      isNull,
    );
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }

    expect(controller.value.getMaxScaleOnAxis(), 20);
    expect(find.text('20×'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_rounded),
          )
          .onPressed,
      isNull,
    );
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
    }
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.remove_rounded),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('zoom keeps the viewer gesture child widget', (tester) async {
    await tester.pumpWidget(app());
    final gesture = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onDoubleTap != null,
    );
    final before = tester.widget<GestureDetector>(gesture);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(identical(tester.widget<GestureDetector>(gesture), before), isTrue);
  });

  testWidgets('pan margin stays 80 screen pixels from 1x through 20x', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    InteractiveViewer viewer() =>
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer().boundaryMargin.left, 80);

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }

    expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 20);
    expect(viewer().boundaryMargin.left * 20, closeTo(80, 0.01));
  });

  testWidgets('searching an edge place does not snap on a tiny scroll', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Search campus places (Ctrl+F)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'West fountain');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'West fountain'));
    await tester.pumpAndSettle();

    final viewer = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), 2.4);
    final center = tester.getSize(viewer).center(Offset.zero);
    final before = controller.toScene(center);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getTopLeft(viewer) + center,
        scrollDelta: const Offset(0, -1),
      ),
    );
    await tester.pump();

    expect((controller.toScene(center) - before).distance, lessThan(2));
  });

  testWidgets('scroll zoom keeps its focal point through 20x', (tester) async {
    await tester.pumpWidget(app());
    final viewer = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final focal = tester.getTopLeft(viewer) + const Offset(250, 180);
    final localFocal = focal - tester.getTopLeft(viewer);
    final scenePoint = controller.toScene(localFocal);

    for (var i = 0; i < 9; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: focal, scrollDelta: const Offset(0, -80)),
      );
      await tester.pump();
      expect(
        (controller.toScene(localFocal) - scenePoint).distance,
        lessThan(2),
        reason: 'scroll step $i at ${controller.value.getMaxScaleOnAxis()}x',
      );
    }
    expect(controller.value.getMaxScaleOnAxis(), 20);
  });

  testWidgets(
    'button and double tap zoom keep the viewport center through 20x',
    (tester) async {
      await tester.pumpWidget(app());
      final viewer = find.byType(InteractiveViewer);
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final center = tester.getSize(viewer).center(Offset.zero);
      final scenePoint = controller.toScene(center);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expect((controller.toScene(center) - scenePoint).distance, lessThan(2));
      }
      for (var i = 0; i < 4; i++) {
        await tester.tapAt(tester.getTopLeft(viewer) + center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(tester.getTopLeft(viewer) + center);
        await tester.pump(const Duration(milliseconds: 400));
        expect((controller.toScene(center) - scenePoint).distance, lessThan(2));
      }
      expect(controller.value.getMaxScaleOnAxis(), 20);
    },
  );

  testWidgets('trackpad pinch keeps its focal point through 20x', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final viewer = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final focal = tester.getTopLeft(viewer) + const Offset(250, 180);
    final localFocal = focal - tester.getTopLeft(viewer);
    final scenePoint = controller.toScene(localFocal);

    for (var i = 0; i < 9; i++) {
      await tester.sendEventToBinding(
        PointerScaleEvent(position: focal, scale: 1.5),
      );
      await tester.pump();
      expect(
        (controller.toScene(localFocal) - scenePoint).distance,
        lessThan(2),
        reason: 'pinch step $i at ${controller.value.getMaxScaleOnAxis()}x',
      );
    }
    expect(controller.value.getMaxScaleOnAxis(), 20);
  });

  testWidgets('zooming out from a panned corner does not snap on scroll', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final viewer = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    await tester.drag(viewer, const Offset(-4000, -4000));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
    }

    final center = tester.getSize(viewer).center(Offset.zero);
    final before = controller.toScene(center);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getTopLeft(viewer) + center,
        scrollDelta: const Offset(0, -1),
      ),
    );
    await tester.pump();
    expect((controller.toScene(center) - before).distance, lessThan(2));
  });

  testWidgets('double tap and keyboard zoom can pass 5x', (tester) async {
    await tester.pumpWidget(app());
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(5));

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
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(7));
  });

  test('map tap radius stays near a pin at 20x', () {
    final projection = CampusMapProjection(const [
      west,
      east,
    ], const Size(800, 600));
    final pin = projection.project(west.anchor!);

    expect(projection.nearest(pin + const Offset(1, 0), zoom: 20), west);
    expect(projection.nearest(pin + const Offset(2, 0), zoom: 20), isNull);
    expect(projection.nearest(pin + const Offset(27, 0)), west);
    expect(projection.nearest(pin + const Offset(28, 0)), isNull);
  });

  testWidgets('tap hit testing uses the live 20x transform', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Water fountains'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    expect(controller.value.getMaxScaleOnAxis(), 20);

    final viewer = find.byType(InteractiveViewer);
    final size = tester.getSize(viewer);
    final pin = CampusMapProjection(const [
      west,
      east,
    ], size).project(west.anchor!);
    final detector = tester.widget<GestureDetector>(
      find.descendant(
        of: viewer,
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onTapUp != null,
        ),
      ),
    );
    detector.onTapUp!(
      TapUpDetails(
        localPosition: pin + const Offset(2, 0),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Close details'), findsNothing);
    detector.onTapUp!(
      TapUpDetails(
        localPosition: pin + const Offset(1, 0),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Close details'), findsOneWidget);
  });

  testWidgets('selecting the list shows useful place details', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Defibrillators'));
    await tester.pumpAndSettle();
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

  test('pin semantics keep a 48 point screen target from 1x to 20x', () {
    CampusMapPainter at(double zoom) => CampusMapPainter(
      features: const [west],
      selectedId: null,
      scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      zoom: zoom,
    );

    expect(
      at(1).semanticsBuilder(const Size(800, 500)).single.rect.width,
      closeTo(48, 0.01),
    );
    expect(
      at(20).semanticsBuilder(const Size(800, 500)).single.rect.width * 20,
      closeTo(48, 0.01),
    );
  });

  test('pin semantics rebuild only after a quarter step of zoom', () {
    CampusMapPainter at(double zoom) => CampusMapPainter(
      features: const [west],
      selectedId: null,
      scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      zoom: zoom,
    );

    expect(at(20).shouldRebuildSemantics(at(20.01)), isFalse);
    expect(at(20).shouldRebuildSemantics(at(19.7)), isTrue);
  });

  test('cached pin paint matches a fresh layout at 1x and 20x', () async {
    const nearby = CampusMapFeature(
      id: 4,
      kind: 'water',
      kindName: 'Water fountains',
      name: 'Nearby fountain',
      geometryType: 'Point',
      coordinates: [
        [GeoCoordinate(-77.6796, 43.08)],
      ],
    );
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
    const size = Size(240, 160);
    final cachedPainter = CampusMapPainter(
      features: const [west, nearby],
      boundsFeatures: const [west, east],
      selectedId: null,
      scheme: scheme,
      zoom: 20,
    );
    expect(
      identical(
        cachedPainter.pinLayoutForTest(size),
        cachedPainter.pinLayoutForTest(size),
      ),
      isTrue,
    );
    Future<List<int>> pixels(double zoom) async {
      final recorder = ui.PictureRecorder();
      final painter = CampusMapPainter(
        features: const [west, nearby],
        boundsFeatures: const [west, east],
        selectedId: null,
        scheme: scheme,
        zoom: zoom,
      );
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(240, 160);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return bytes!.buffer.asUint8List();
    }

    final first = await pixels(1);
    expect(await pixels(1), orderedEquals(first));
    CampusMapPainter.resetGeometryCacheForTest();
    expect(await pixels(1), orderedEquals(first));

    final close = await pixels(20);
    expect(close, isNot(orderedEquals(first)));
    expect(await pixels(20), orderedEquals(close));
    CampusMapPainter.resetGeometryCacheForTest();
    expect(await pixels(20), orderedEquals(close));
  });

  testWidgets('priming uses the shared skeleton', (tester) async {
    await tester.pumpWidget(app(priming: true));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading campus map'), findsOneWidget);
  });

  testWidgets('the Places and Events switch is the shared segmented picker', (tester) async {
    await tester.pumpWidget(app());

    expect(find.byType(SegmentedPicker<bool>), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(
      find.descendant(of: find.byType(SegmentedPicker<bool>), matching: find.text('Places')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(SegmentedPicker<bool>), matching: find.text('Events')),
      findsOneWidget,
    );
  });

  testWidgets('events mode reports mapped and unmapped events', (tester) async {
    final today = CampusTime.wall(2026, 10, 8, 10);
    RitClock.pin(today);
    addTearDown(RitClock.reset);
    await tester.pumpWidget(
      app(
        events: [
          CampusEvent(
            uid: 'mapped',
            source: 'test',
            title: 'GOL workshop',
            startsAt: today,
            location: 'GOL 1300',
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
    expect(find.text('GOL workshop'), findsOneWidget);
    expect(find.text('Mystery event'), findsNothing);
  });
}
