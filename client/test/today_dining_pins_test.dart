/// Today's dining card puts pinned places first, as the Dining tab does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(() async {
    RitClock.reset();
    // the housing card reloads prefs from the shared cache
    if (Preferences.instance.isPinned(40)) await Preferences.instance.togglePinned(40);
    Preferences.instance.resetForTests();
  });

  Future<void> pumpToday(WidgetTester tester, List<DiningLocation> dining) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 5000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok(dining),
          events: _ok<CampusEvent>(const []),
          chefs: _ok<MenuItem>(const []),
          areas: _ok<HousingArea>(const []),
          onRefresh: () async {},
          onGoToTab: (_) {},
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  // sensor places sort first unpinned, so the pin has to beat them
  final places = [
    for (var i = 0; i < 5; i++) DiningLocation(id: i + 1, name: 'Busy hall $i', isOpen: true, occupancy: Occupancy(percentFull: 50 + i)),
    const DiningLocation(id: 40, name: 'Zebra grill', isOpen: true),
  ];

  testWidgets('a pinned open place shows first on Today', (tester) async {
    await Preferences.instance.togglePinned(40);
    await pumpToday(tester, places);

    expect(find.text('Zebra grill'), findsOneWidget);
    final pinned = tester.getTopLeft(find.text('Zebra grill')).dy;
    for (var i = 0; i < 5; i++) {
      final other = find.text('Busy hall $i');
      if (other.evaluate().isEmpty) continue;
      expect(pinned, lessThan(tester.getTopLeft(other).dy), reason: 'Busy hall $i');
    }
  });

  testWidgets('pinning after the first paint reorders the card', (tester) async {
    await pumpToday(tester, places);
    expect(find.text('Zebra grill'), findsNothing);

    await Preferences.instance.togglePinned(40);
    await tester.pump();
    expect(find.text('Zebra grill'), findsOneWidget);
  });
}
