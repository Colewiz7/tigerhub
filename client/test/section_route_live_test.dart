/// A pushed Campus section follows data that lands after it opened.
///
/// On a phone the route used to be built from the section captured at the tap,
/// so a response arriving afterwards updated Campus underneath and left the
/// loading placeholder on screen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

// holds the gated paths until the test lets them go
class _GatedBackend implements Backend {
  _GatedBackend(this.config, Set<String> gated) : gates = {for (final p in gated) p: Completer<void>()};

  final StaticConfig config;
  final Map<String, Completer<void>> gates;

  Map<String, dynamic> _envelope(List<dynamic> data) => {'data': data, 'stale': false, 'last_updated': null};

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    await gates[path]?.future;
    switch (path) {
      case '/post-offices':
        return _envelope(config.postOffices);
      case '/housing/areas':
        return _envelope(config.housingAreas);
      case '/makerspace/hours':
        return {'items': config.shedSpaces};
      case '/makerspace/rooms':
        return _envelope([
          {'room': 'Wood Shop', 'machines': 15, 'available': 12, 'in_use': 3},
        ]);
      case '/recreation/hours':
        final rows = parseRecreation(File('test/fixtures/recreation.html').readAsStringSync(), today: DateTime.utc(2026, 8, 30));
        return _envelope(recreationFacilities({'rows': rows}));
      case '/campus/places':
        final kinds = <String, List<Map<String, dynamic>>>{};
        parseCampusPlaces(File('test/fixtures/maps_category_35.data').readAsStringSync()).forEach((subId, places) => kinds[placeKinds[subId]!.$1] = places);
        return _envelope(placeKindSummary({'kinds': kinds}));
    }
    throw UnimplementedError(path);
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StaticConfig config;

  setUpAll(() {
    final files = <String, Map<String, dynamic>>{};
    for (final name in ['dining_categories', 'post_offices', 'housing_areas', 'shed_hours', 'fd_locations']) {
      files[name] = jsonDecode(File('assets/config/$name.json').readAsStringSync()) as Map<String, dynamic>;
    }
    StaticConfig.overrideForTesting(files);
    config = StaticConfig.instance;
  });

  // the cache singleton keeps the first platform, so wipe rather than swap
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  setUp(() async {
    await SharedPreferencesAsync().clear();
    RitClock.pin(CampusTime.wall(2026, 9, 15, 16, 15));
  });

  tearDown(RitClock.reset);

  Future<_GatedBackend> pumpPhone(WidgetTester tester, Set<String> gated) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);
    final backend = _GatedBackend(config, gated);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(
          body: CampusScreen(
            api: ApiClient(backend: backend),
            now: DateTime(2026, 8, 30),
            areas: Result(
              value: Collection(data: config.housingAreas.map(HousingArea.fromJson).toList(), stale: false),
              state: DataState.ok,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return backend;
  }

  final cases = [
    ('Mail', '/post-offices', 'Loading post offices', 'Global Village Post Office'),
    ('Find on campus', '/campus/places', 'Loading places', 'Water'),
    ('Gym and pool', '/recreation/hours', 'Loading facility hours', 'Aquatic'),
    ('SHED makerspace', '/makerspace/rooms', 'Loading equipment', 'Wood Shop'),
  ];

  for (final (title, path, placeholder, data) in cases) {
    testWidgets('$title opened before its data replaces the placeholder', (tester) async {
      final backend = await pumpPhone(tester, {path});

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text(placeholder), findsOneWidget);

      backend.gates[path]!.complete();
      await tester.pumpAndSettle();

      expect(find.text(placeholder), findsNothing);
      expect(find.textContaining(data), findsWidgets);
    });
  }
}
