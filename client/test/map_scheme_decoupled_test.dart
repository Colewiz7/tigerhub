/// The campus map keeps its own fixed colours: switching the colour scheme
/// must not move a pin, the legend, or the controls drawn over it.
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
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/map_style.dart';

class _MapBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/campus/map') {
      return {
        'data': parseCampusMapFeatures(File('test/fixtures/maps_category_35.data').readAsStringSync()),
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
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('pin colours come from the map palette, by brightness only', () {
    for (final b in Brightness.values) {
      final map = MapPalette.of(b);
      expect(mapPinPalette('water', b), (map.pinUtility, map.onPinUtility));
      expect(mapPinPalette('aed', b), (map.pinSafety, map.onPinSafety));
      expect(mapPinPalette('library', b), (map.pinPlace, map.onPinPlace));
    }
  });

  testWidgets('the controls over the map ignore the scheme', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    Future<List<Color?>> read(AppScheme choice) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(SchemeController.forChoice(choice)),
          home: Scaffold(body: MapScreen(api: ApiClient(backend: _MapBackend()))),
        ),
      );
      await tester.pumpAndSettle();
      final hint = find.ancestor(of: find.text('Zoom in for walking paths'), matching: find.byType(Material)).first;
      final hintIcon = find.descendant(of: hint, matching: find.byType(Icon)).first;
      final north = find.ancestor(of: find.text('N'), matching: find.byType(Material)).first;
      return [
        tester.widget<Material>(hint).color,
        tester.widget<Icon>(hintIcon).color,
        tester.widget<Material>(north).color,
        tester.widget<Text>(find.text('Zoom in for walking paths')).style?.color,
        tester.widget<Text>(find.text('N')).style?.color,
      ];
    }

    final espresso = await read(AppScheme.espresso);
    expect(espresso.every((c) => c != null), isTrue);
    expect(await read(AppScheme.mocha), espresso);
    expect(await read(AppScheme.slate), espresso);
  });
}
