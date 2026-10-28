/// Shared setup for the Dining tab tests: real groups, an empty backend.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

class EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

// ids from the real table: 21 Dorm side, 32 SAU, 23 Global Village, 481 Other, 461 RIT Inn
DiningLocation place(int id, String name, {bool open = true}) => DiningLocation(id: id, name: name, isOpen: open);

final List<DiningLocation> sampleDining = [
  place(21, "Gracie's"),
  place(31, 'Beanz', open: false),
  place(32, "Ben and Jerry's"),
  place(23, 'Crossroads'),
  place(481, 'Bytes', open: false),
  place(461, 'Petals'),
];

void setUpDining() {
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await ResponseCache.instance.prune(olderThan: const Duration(days: -1));
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
    final groups = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
    StaticConfig.overrideForTesting({'dining_groups': groups});
  });
  tearDown(() {
    RitClock.reset();
    Preferences.instance.resetForTests();
  });
}

Future<void> pumpDiningScreen(
  WidgetTester tester, {
  List<DiningLocation>? places,
  Size size = const Size(390, 1600),
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: DiningScreen(
          api: ApiClient(backend: EmptyBackend()),
          result: Result(value: Collection(data: places ?? sampleDining, stale: false), state: DataState.ok),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
