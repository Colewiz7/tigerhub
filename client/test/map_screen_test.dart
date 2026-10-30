/// The campus map, on its own tab.
///
/// This assertion used to live in the Campus screen's tests, because the map
/// was a section there. It moved with the map rather than being deleted: what
/// it checks, that real captured GeoJSON actually reaches the canvas, is worth
/// keeping wherever the map lives.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'golden_harness.dart' show captureOverflows, loadGoldenFonts;

class _MapBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    if (path == '/campus/map') {
      return {
        'data': parseCampusMapFeatures(
          File('test/fixtures/maps_category_35.data').readAsStringSync(),
        ),
        'stale': false,
        'last_updated': null,
      };
    }
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('renders the captured GeoJSON', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: MapScreen(api: ApiClient(backend: _MapBackend())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Fit campus'), findsOneWidget);
    expect(find.byTooltip('Search campus places (Ctrl+F)'), findsOneWidget);
    expect(find.byTooltip('Filter map places'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // real fonts, the test font is wider than Rubik
  group('map chrome', () {
  setUpAll(loadGoldenFonts);
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets('${size.width.toInt()} wide at ${textScale}x: nothing on the map screen overflows, the zoom hint stays in view and the legend clears north', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final overflows = await captureOverflows(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
              home: MediaQuery(
                data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
                child: Scaffold(body: MapScreen(api: ApiClient(backend: _MapBackend()))),
              ),
            ),
          );
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);

        final map = tester.getRect(find.byType(InteractiveViewer));
        bool inside(Rect r) => r.left >= map.left && r.right <= map.right && r.top >= map.top && r.bottom <= map.bottom;
        final hint = find.text('Zoom in for walking paths');
        expect(inside(tester.getRect(find.ancestor(of: hint, matching: find.byType(Material)).first)), isTrue);
        expect(inside(tester.getRect(hint)), isTrue);
        // wraps, never cut short
        final paragraph = tester.renderObject<RenderParagraph>(hint);
        expect(paragraph.didExceedMaxLines, isFalse);
        // the longest word fits the box
        expect(paragraph.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width + 0.5));

        final legend = tester.getRect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MapLegend'));
        final north = tester.getRect(find.byTooltip('North up'));
        expect(inside(legend), isTrue);
        expect(legend.overlaps(north), isFalse, reason: '$legend under $north');
      }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
    }
  }

  // the longest names in the capture, so the panel has the most to fit
  final features = parseCampusMapFeatures(File('test/fixtures/maps_category_35.data').readAsStringSync()).map(CampusMapFeature.fromJson).toList();
  String longest(Iterable<CampusMapFeature> some) => some.map((f) => f.name).reduce((a, b) => a.length >= b.length ? a : b);
  final place = longest(features.where((f) => f.geometryType == 'Point' && !f.kind.startsWith('_')));
  final buildings = features.where((f) => f.kind == '_campus' && (f.building?.length ?? 0) >= 2);
  final building = longest(buildings);
  final code = buildings.first.building!;
  final now = DateTime.now();
  final events = Result(
    value: Collection<CampusEvent>(
      data: [
        for (var i = 0; i < 3; i++)
          CampusEvent(uid: 'e$i', source: 'test', title: 'Student government open forum on dining and housing $i', startsAt: now, location: 'Room 2000 $code', organizer: 'Student Government Association'),
      ],
      stale: false,
    ),
    state: DataState.ok,
  );

  Future<void> search(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Search campus places (Ctrl+F)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.text(name)).first);
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final textScale in const [1.0, 2.0]) {
      for (final (what, close) in const [('place', 'Close details'), ('building', 'Close details'), ('event', 'Close event details')]) {
        testWidgets('${size.width.toInt()} wide at ${textScale}x: a selected $what panel fits its text', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final overflows = await captureOverflows(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
                home: MediaQuery(
                  data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(body: MapScreen(api: ApiClient(backend: _MapBackend()), events: events)),
                ),
              ),
            );
            await tester.pumpAndSettle();
            switch (what) {
              case 'place':
                await search(tester, place);
              case 'building':
                await search(tester, building);
              default:
                await tester.tap(find.text('Events'));
                await tester.pumpAndSettle();
                // three at one building make one card
                await tester.tap(find.text('3 events'));
                await tester.pumpAndSettle();
            }
          });
          expect(find.byTooltip(close), findsOneWidget, reason: 'the $what panel is open');
          expect(overflows, isEmpty);
          // selecting zooms in, and 2.4× must stay one line
          final readout = tester.renderObject<RenderParagraph>(find.textContaining('×'));
          final oneLine = TextPainter(text: TextSpan(text: '1×', style: readout.text.style), textScaler: readout.textScaler, textDirection: TextDirection.ltr)..layout();
          expect(readout.size.height, oneLine.height);
          oneLine.dispose();
          // the close button has its own small Material, the panel is the wide one
          final panel = [
            for (final e in find.ancestor(of: find.byTooltip(close), matching: find.byType(Material)).evaluate())
              if (e.renderObject case final RenderBox box) box.localToGlobal(Offset.zero) & box.size,
          ].firstWhere((r) => r.width > 200);
          expect(panel.height, greaterThanOrEqualTo(146));
          expect(panel.bottom, lessThanOrEqualTo(size.height));
        }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
      }
    }
  }
  });

  testWidgets('survives being disposed mid load', (tester) async {
    // The tab can be left before the map's own subscription delivers, and a
    // dangling one would then call setState on a dead screen.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapScreen(api: ApiClient(backend: _MapBackend())),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
