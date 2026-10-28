/// Today's events card follows the saved event filters, as the Events tab does.
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
    // wed oct 14 2026, noon on campus
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(() async {
    RitClock.reset();
    // the housing card reloads prefs from the shared cache
    await Preferences.instance.clearMutes();
    Preferences.instance.resetForTests();
  });

  Future<void> pumpToday(WidgetTester tester, List<CampusEvent> events) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 5000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok<DiningLocation>(const []),
          events: _ok(events),
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

  final robots = CampusEvent(uid: 'robots', source: 'test', title: 'Robot build night', startsAt: DateTime.utc(2026, 10, 14, 22), endsAt: DateTime.utc(2026, 10, 14, 23), organizer: 'Robotics Club', organizerKey: 'robotics');
  final chess = CampusEvent(uid: 'chess', source: 'test', title: 'Chess night', startsAt: DateTime.utc(2026, 10, 14, 21), endsAt: DateTime.utc(2026, 10, 14, 23), organizer: 'Chess Club', organizerKey: 'chess');
  final resume = CampusEvent(uid: 'resume', source: 'test', title: 'Resume workshop', startsAt: DateTime.utc(2026, 10, 14, 20), endsAt: DateTime.utc(2026, 10, 14, 21), organizer: 'Career Services', organizerKey: 'careers');

  testWidgets('a muted organizer is not on Today', (tester) async {
    await Preferences.instance.setMuted('chess', true);
    await pumpToday(tester, [robots, chess]);

    expect(find.text('Robot build night'), findsWidgets);
    expect(find.text('Chess night'), findsNothing);
  });

  testWidgets('a title with a hide word is not on Today', (tester) async {
    await pumpToday(tester, [robots, resume]);

    expect(find.text('Robot build night'), findsWidgets);
    expect(find.text('Resume workshop'), findsNothing);
  });

  testWidgets('turning the keyword rules off brings it back', (tester) async {
    await pumpToday(tester, [resume]);
    expect(find.text('Resume workshop'), findsNothing);
    await Preferences.instance.setKeywordRulesEnabled(false);
    await tester.pump();

    expect(find.text('Resume workshop'), findsWidgets);
    await Preferences.instance.setKeywordRulesEnabled(true);
  });

  testWidgets('muting after the first paint takes the event off', (tester) async {
    await pumpToday(tester, [chess]);
    expect(find.text('Chess night'), findsWidgets);

    await Preferences.instance.setMuted('chess', true);
    await tester.pump();
    expect(find.text('Chess night'), findsNothing);
  });
}
