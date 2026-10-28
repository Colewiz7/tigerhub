/// Today shows what is still ahead: an event that has ended drops off.
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
    // wed oct 14 2026, noon on campus
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(RitClock.reset);

  testWidgets('an ended event is gone from Today, an upcoming one stays', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 5000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok<DiningLocation>(const []),
          events: _ok([
            CampusEvent(uid: 'old', source: 'test', title: 'Morning yoga', startsAt: DateTime.utc(2026, 10, 14, 12), endsAt: DateTime.utc(2026, 10, 14, 13), organizer: 'Rec', organizerKey: 'rec'),
            CampusEvent(uid: 'new', source: 'test', title: 'Robot build night', startsAt: DateTime.utc(2026, 10, 14, 22), endsAt: DateTime.utc(2026, 10, 14, 23), organizer: 'Robotics Club', organizerKey: 'robotics'),
          ]),
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

    expect(find.text('Robot build night'), findsWidgets);
    expect(find.text('Morning yoga'), findsNothing);
    expect(find.text('Ended'), findsNothing);
  });
}
