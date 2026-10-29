/// The Shuttles card: routes still running from home and until when, from
/// the published service windows. It never claims a departure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/shuttles_card.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/shuttles.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/compact_card.dart';

final _schedule = ShuttleSchedule.parse(jsonDecode(File('assets/config/shuttles.json').readAsStringSync()) as Map<String, dynamic>);

// wed oct 14, sat oct 17, sun oct 18, mon oct 19 2026, campus wall clock
DateTime _wed(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);

void main() {
  group('the answer', () {
    test('global village on a weekday afternoon is 3 routes until 11:16 PM', () {
      expect(shuttlesCompact(_schedule, 'global-village', _wed(15)), (value: '3 routes', caption: 'until 11:16 PM', quiet: false));
    });

    test('before any route starts it says how many and from when', () {
      expect(shuttlesCompact(_schedule, 'global-village', _wed(4, 30)), (value: '3 routes', caption: 'from 5 AM', quiet: true));
    });

    test('routes that have ended no longer count', () {
      // route 4 ends 6 PM and 5 ends 4:30 PM, 3 runs to 11:16 PM
      expect(shuttlesCompact(_schedule, 'global-village', _wed(19)).value, '1 route');
    });

    test('after the last route it is done for the day', () {
      expect(shuttlesCompact(_schedule, 'global-village', _wed(23, 30)).value, 'Done today');
    });

    test('a weekend route that runs past midnight still counts at 12:10 AM', () {
      final answer = shuttlesCompact(_schedule, 'global-village', DateTime(2026, 10, 18, 0, 10));
      expect(answer.value, '1 route');
      expect(answer.caption, 'until 12:33 AM');
    });

    test('monday just after midnight still counts sunday night, not the 5 AM route', () {
      final answer = shuttlesCompact(_schedule, 'global-village', DateTime(2026, 10, 19, 0, 10));
      expect(answer, (value: '1 route', caption: 'until 12:33 AM', quiet: false));
    });

    test('no home says set home, an area with no routes says so', () {
      expect(shuttlesCompact(_schedule, null, _wed(15)).value, 'Set home');
      expect(shuttlesCompact(_schedule, 'greek-houses', _wed(15)).value, 'No routes');
    });

    test('before the table loads there is no value', () {
      expect(shuttlesCompact(null, 'global-village', _wed(15)).value, isNull);
    });

    test('every answer fits a compact card and never claims a departure', () {
      for (final area in ['global-village', 'residence-halls', 'perkins-green', 'riverknoll', 'university-commons', 'greek-houses', null]) {
        for (var day = 12; day <= 18; day++) {
          for (var minute = 0; minute < 1440; minute += 15) {
            final answer = shuttlesCompact(_schedule, area, DateTime(2026, 10, day, minute ~/ 60, minute % 60));
            final text = '${answer.value ?? ''} ${answer.caption ?? ''}'.toLowerCase();
            for (final word in ['next', 'depart', 'arriv', 'leaves']) {
              expect(text.contains(word), isFalse, reason: '"$text" says $word');
            }
            expect((answer.value ?? '').length, lessThanOrEqualTo(12), reason: answer.value);
          }
        }
      }
    });
  });

  test('shuttles is a compact card type in the library', () {
    expect(ModuleType.byId('shuttles'), ModuleType.shuttles);
    expect(supportedSizes[ModuleType.shuttles], [CardSize.compact]);
    expect(moduleLabels[ModuleType.shuttles], 'Shuttles');
    expect(moduleIcons[ModuleType.shuttles], isNotNull);
    expect(compactBodyTypes, contains(ModuleType.shuttles));
  });

  group('on a phone', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      Preferences.instance.resetForTests();
      ShuttleSchedule.overrideForTesting(_schedule);
      // wed oct 14 2026, 3 PM on campus
      RitClock.pin(DateTime.utc(2026, 10, 14, 19));
    });
    tearDown(() {
      RitClock.reset();
      ShuttleSchedule.overrideForTesting(null);
      Preferences.instance.resetForTests();
    });

    testWidgets('the card reads from home and opens the route list', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await Preferences.instance.setHome(area: 'global-village');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: const Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 174, child: ShuttlesCard()))),
      ));
      await tester.pump();
      expect(find.byType(CompactCard), findsOneWidget);
      expect(find.text('3 routes'), findsOneWidget);
      expect(find.text('until 11:16 PM'), findsOneWidget);
      await tester.tap(find.text('3 routes'));
      await tester.pumpAndSettle();
      // per-route detail stays one tap from Today
      expect(find.text('Today from home'), findsOneWidget);
      expect(find.textContaining('3 · Campus Connection'), findsOneWidget);
      expect(find.textContaining('TripShot'), findsOneWidget);
    });
  });
}
