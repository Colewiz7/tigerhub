/// The campus map, on its own tab.
///
/// This assertion used to live in the Campus screen's tests, because the map
/// was a section there. It moved with the map rather than being deleted: what
/// it checks, that real captured GeoJSON actually reaches the canvas, is worth
/// keeping wherever the map lives.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'golden_harness.dart' show Overflow, captureOverflows, loadGoldenFonts;

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
    expect(find.byTooltip('Filter map places'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // real fonts, the test font is wider than Rubik
  group('map chrome', () {
  setUpAll(loadGoldenFonts);
  // lines of the legend and the zoom row, other parts of the screen have their own tests
  final source = File('lib/widgets/campus_map.dart').readAsLinesSync();
  bool inClass(String name, int line) {
    final start = source.indexWhere((l) => l.startsWith('class $name ')) + 1;
    final end = source.indexWhere((l) => l.startsWith('class '), start) + 1;
    return line >= start && line < end;
  }
  bool chrome(Overflow o) {
    final line = int.parse(o.where.split(':').last);
    return o.where.startsWith('lib/widgets/campus_map.dart') && (inClass('_MapLegend', line) || inClass('_MapZoomControls', line));
  }
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets('${size.width.toInt()} wide at ${textScale}x: the zoom hint stays in view and the legend clears north', (tester) async {
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
        expect(overflows.where(chrome), isEmpty);

        final map = tester.getRect(find.byType(InteractiveViewer));
        bool inside(Rect r) => r.left >= map.left && r.right <= map.right && r.top >= map.top && r.bottom <= map.bottom;
        final hint = find.text('Zoom in for walking paths');
        expect(inside(tester.getRect(find.ancestor(of: hint, matching: find.byType(Material)).first)), isTrue);
        expect(inside(tester.getRect(hint)), isTrue);

        final legend = tester.getRect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MapLegend'));
        final north = tester.getRect(find.byTooltip('North up'));
        expect(inside(legend), isTrue);
        expect(legend.overlaps(north), isFalse, reason: '$legend under $north');
      }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
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
