import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_paths.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/campus_map.dart';

import 'golden_harness.dart';

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

Future<void> _loadPaths(WidgetTester tester) async {
  CampusPaths.resetForTest();
  final paths = await tester.runAsync(() => CampusPaths.load());
  expect(paths?.isEmpty, isFalse);
}

void _expectPaintedPaths(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is CampusMapPainter,
    ),
  );
  expect((paint.painter! as CampusMapPainter).paths.isEmpty, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpGoldenFonts('map_screen_golden_test.dart');

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final size in [const Size(390, 844), const Size(430, 932)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final textScale in [1.0, 2.0]) {
        goldenWidgets(
          'map screen ${size.width.toInt()}x${size.height.toInt()} ${brightness.name} ${textScale}x',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            addTearDown(tester.view.reset);
            await _loadPaths(tester);
            await tester.pumpWidget(
              MaterialApp(
                theme: goldenTheme(
                  AppTheme.from(
                    ColorScheme.fromSeed(
                      seedColor: const Color(0xFFF76902),
                      brightness: brightness,
                    ),
                  ),
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Scaffold(
                    body: MapScreen(api: ApiClient(backend: _MapBackend())),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            _expectPaintedPaths(tester);
            await expectLater(
              find.byType(Scaffold),
              matchesGoldenFile(
                'goldens/map_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_text${textScale.toInt()}.png',
              ),
            );
          },
        );
      }
    }
  }

  goldenWidgets('map screen 390x844 light at 20x', (tester) async {
    const size = Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await _loadPaths(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTheme(
          AppTheme.from(
            ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
          ),
        ),
        home: Scaffold(
          body: MapScreen(api: ApiClient(backend: _MapBackend())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectPaintedPaths(tester);
    final features = parseCampusMapFeatures(
      File('test/fixtures/maps_category_35.data').readAsStringSync(),
    ).map(CampusMapFeature.fromJson).toList();
    final points =
        features
            .where(
              (feature) =>
                  feature.geometryType == 'Point' &&
                  !feature.kind.startsWith('_'),
            )
            .toList()
          ..sort((a, b) => a.kindName.length.compareTo(b.kindName.length));
    final feature = points.first;
    await tester.tap(find.byTooltip('Filter map places'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(feature.kindName).last);
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final viewport = tester.getSize(find.byType(InteractiveViewer));
    final center = viewport.center(Offset.zero);
    final projection = CampusMapProjection(
      features,
      viewport,
      boundsFeatures: features,
    );
    final pin = projection.project(feature.anchor!);
    expect(viewer.maxScale, 20);
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    final controller = viewer.transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), 20);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_rounded),
          )
          .onPressed,
      isNull,
    );
    controller.value = controller.value.clone()
      ..setEntry(0, 3, center.dx - pin.dx * 20)
      ..setEntry(1, 3, center.dy - pin.dy * 20);
    await tester.pump();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/map_390x844_light_20x.png'),
    );
  });
}
