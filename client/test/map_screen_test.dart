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

class _MapBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
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

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: Scaffold(body: MapScreen(api: ApiClient(backend: _MapBackend()))),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Fit campus'), findsOneWidget);
    expect(find.text('Water fountains'), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives being disposed mid load', (tester) async {
    // The tab can be left before the map's own subscription delivers, and a
    // dangling one would then call setState on a dead screen.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MapScreen(api: ApiClient(backend: _MapBackend()))),
    ));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
