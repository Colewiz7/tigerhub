/// Break days run the break shuttle only, and holidays their reduced service,
/// from dates in shuttles.json rather than a hard-coded day. Every instant
/// here is utc and read on the campus clock, so any device zone agrees.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/shuttles_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/shuttles.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

final _schedule = ShuttleSchedule.parse(jsonDecode(File('assets/config/shuttles.json').readAsStringSync()) as Map<String, dynamic>);

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  List<int> numbers(String? area, DateTime day) => [for (final r in _schedule.routesOn(area, day)) r.number];

  group('the schedule', () {
    test('fall break, monday and tuesday, runs only the break shuttle', () {
      expect(numbers('global-village', DateTime(2026, 10, 12)), [14]);
      expect(numbers('global-village', DateTime(2026, 10, 13)), [14]);
      expect(numbers('perkins-green', DateTime(2026, 10, 12)), [14]);
      expect(numbers('residence-halls', DateTime(2026, 10, 13)), [14]);
    });

    test('the days either side keep their normal service', () {
      expect(numbers('global-village', DateTime(2026, 10, 11)), [12, 13]);
      expect(numbers('global-village', DateTime(2026, 10, 14)), [3, 4, 5]);
    });

    test('spring break covers its weekends and ends after the 14th', () {
      expect(numbers('global-village', DateTime(2027, 3, 7)), [14]);
      expect(numbers('global-village', DateTime(2027, 3, 10)), [14]);
      expect(numbers('global-village', DateTime(2027, 3, 14)), [14]);
      expect(numbers('global-village', DateTime(2027, 3, 15)), [3, 4, 5]);
    });

    test('an area with no table has no break service either', () {
      expect(numbers('greek-houses', DateTime(2026, 10, 12)), isEmpty);
    });

    test('Labor Day comes from the same data, the same for every area', () {
      expect(_schedule.holidayOn(DateTime(2026, 9, 7))?.name, 'Labor Day');
      for (final area in ['global-village', 'perkins-green', 'greek-houses', null]) {
        expect(numbers(area, DateTime(2026, 9, 7)), [1, 14], reason: '$area');
      }
      expect(_schedule.holidayOn(DateTime(2026, 9, 8)), isNull);
    });
  });

  group('Today at campus instants', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      Preferences.instance.resetForTests();
    });
    tearDown(RitClock.reset);

    // edt, campus is utc - 4
    final cases = <String, (DateTime, String?, String?)>{
      'fall break monday, 10 AM on campus': (DateTime.utc(2026, 10, 12, 14), '1 route', 'until 12:06 AM'),
      'last break night, 11:30 PM on campus': (DateTime.utc(2026, 10, 14, 3, 30), '1 route', 'until 12:06 AM'),
      'first day back, 12:30 AM on campus': (DateTime.utc(2026, 10, 14, 4, 30), '3 routes', 'from 5 AM'),
      'sunday before the break, 11:59 PM on campus': (DateTime.utc(2026, 10, 12, 3, 59), '1 route', 'until 12:33 AM'),
    };
    for (final MapEntry(key: name, value: (instant, value, caption)) in cases.entries) {
      test(name, () {
        RitClock.pin(instant);
        final answer = shuttlesCompact(_schedule, 'global-village', CampusTime.wallNow());
        expect(answer.value, value);
        expect(answer.caption, caption);
      });
    }
  });

  testWidgets('Campus names the break and lists only the break shuttle', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 12, 14));
    ShuttleSchedule.overrideForTesting(_schedule);
    addTearDown(() {
      RitClock.reset();
      ShuttleSchedule.overrideForTesting(null);
      Preferences.instance.resetForTests();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await Preferences.instance.setHome(area: 'global-village');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: CampusScreen(
          api: ApiClient(backend: _EmptyBackend()),
          areas: const Result(value: Collection(data: [HousingArea(id: 'global-village', name: 'Global Village')], stale: false), state: DataState.ok),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shuttles'));
    await tester.pumpAndSettle();

    expect(find.text('Fall break service'), findsOneWidget);
    expect(find.textContaining('14 · Campus & Inn Break'), findsOneWidget);
    expect(find.textContaining('3 · Campus Connection'), findsNothing);
  });
}
