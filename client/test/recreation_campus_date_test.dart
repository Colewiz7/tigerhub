/// Recreation "today" follows the campus calendar date, not the device's.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _RecBackend implements Backend {
  _RecBackend(this.facilities);

  final List<Map<String, dynamic>> facilities;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    final data = path == '/recreation/hours' ? facilities : <dynamic>[];
    return {'data': data, 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Map<String, dynamic> _day(String date) => {
  'service_date': date,
  'spans': [
    {'opens_at': '09:00', 'closes_at': '21:00'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 23:30 EDT on Aug 30, which is already Aug 31 in Tokyo and still Aug 30 in LA
  final lateCampusEvening = DateTime.utc(2026, 8, 31, 3, 30);

  setUpAll(() {
    final files = <String, Map<String, dynamic>>{};
    for (final name in [
      'dining_categories',
      'post_offices',
      'housing_areas',
      'shed_hours',
      'fd_locations',
    ]) {
      files[name] = jsonDecode(
        File('assets/config/$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    }
    StaticConfig.overrideForTesting(files);
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    RitClock.pin(lateCampusEvening);
  });

  tearDown(RitClock.reset);

  test('dayOn picks the campus day whatever the device zone is', () {
    final f = RecreationFacility.fromJson({
      'name': 'Pool',
      'days': [_day('2026-08-30'), _day('2026-08-31')],
    });
    final today = CampusTime.wallDate();
    expect(today.day, 30);
    expect(f.dayOn(today)!.serviceDate.day, 30);
  });

  test('a utc midnight service_date keeps its calendar day', () {
    final d = RecreationDay.fromJson({'service_date': '2026-08-30T00:00:00Z'});
    expect(
      (d.serviceDate.year, d.serviceDate.month, d.serviceDate.day),
      (2026, 8, 30),
    );
  });

  Future<void> openRec(
    WidgetTester tester,
    List<Map<String, dynamic>> facilities,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1500, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: CampusScreen(
            api: ApiClient(backend: _RecBackend(facilities)),
            now: DateTime(2026, 8, 30),
            areas: const Result(value: null, state: DataState.priming),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gym and pool'));
    await tester.pumpAndSettle();
  }

  testWidgets('campus row with today dropped shows hours unavailable', (
    tester,
  ) async {
    await openRec(tester, [
      {
        'name': 'Aquatics Center',
        'days': [
          {'closed': true},
          _day('2026-08-31'),
        ],
      },
    ]);
    expect(find.text('Hours unavailable'), findsOneWidget);
    expect(find.text('9:00 AM to 9:00 PM'), findsNothing);
  });

  testWidgets('week sheet labels the campus day Today', (tester) async {
    await openRec(tester, [
      {
        'name': 'Aquatics Center',
        'days': [_day('2026-08-30'), _day('2026-08-31')],
      },
    ]);
    await tester.tap(find.text('Aquatics Center'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
  });
}
