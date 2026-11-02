/// The "How busy" chart with the shape of real maps.rit.edu payloads.
///
/// A live reading carries today = 0 for every hour not yet reached, so a chart
/// scaled to today alone is a row of slivers. These tests use the captured
/// Crossroads payload rather than a synthetic ramp.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/maps_occupancy.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/dining_detail_sheet.dart';

import 'golden_harness.dart';
import 'package:tigerhub/widgets/occupancy_chart.dart';

List<OccupancyHour> _real() => OccupancyHistory.fromJson(
  parseOccupancy(
    File('test/fixtures/maps_occupancy_123.data').readAsStringSync(),
    123,
  )!,
).hourly;

/// The real typical day with today counted so far: hours 7 to 12 filled in,
/// nothing yet after noon, as a live reading looks at lunchtime.
List<OccupancyHour> _openDay() => [
  for (final h in _real())
    OccupancyHour(
      hour: h.hour,
      today: h.hour >= 7 && h.hour <= 12 ? (h.average * 1.2).round() + 1 : 0,
      oneWeekAgo: h.oneWeekAgo,
      average: h.average,
    ),
];

Widget _wrap(Widget child, AppScheme scheme) => MaterialApp(
  theme: AppTheme.from(SchemeController(initial: scheme).scheme),
  home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: child)),
);

class _Backend implements Backend {
  _Backend(this.occupancy);
  final Object occupancy;

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path.endsWith('/occupancy')) {
      if (occupancy is Map<String, dynamic>) return occupancy as Map<String, dynamic>;
      throw occupancy;
    }
    return {'data': <dynamic>[]};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  for (final scheme in AppScheme.values) {
    testWidgets('real data draws visible bars in ${scheme.label}', (tester) async {
      // The real payload's own hours 0 to 2 carry a few late-night people,
      // which hid the problem. Opening morning: nothing counted yet today.
      final morning = [
        for (final h in _real())
          OccupancyHour(
            hour: h.hour,
            today: h.hour < 3 ? 0 : h.today,
            oneWeekAgo: h.oneWeekAgo,
            average: h.average,
          ),
      ];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(OccupancyChart(hourly: morning, nowHour: 12), scheme));
      expect(find.byKey(const ValueKey('occupancy-unavailable')), findsNothing);

      // Every hour has a typical bar with a real width and height. A childless
      // box under loose constraints measured 0px wide, so height alone proved
      // nothing.
      final typical = [
        for (var h = 0; h < 24; h++)
          tester.getRect(find.byKey(ValueKey('occupancy-typical-$h'))),
      ];
      for (var h = 0; h < 24; h++) {
        expect(typical[h].width, greaterThanOrEqualTo(4), reason: 'hour $h has no width');
        expect(typical[h].height, greaterThan(0), reason: 'hour $h has no height');
      }
      // The tallest typical bar (hour 12, 67 against a peak of 67) is the
      // full 96px plot.
      expect(typical[12].height, closeTo(96, 0.5));
      // Side by side: no overlap, a gap between neighbours, all inside the
      // 350px the chart has at 390 wide.
      for (var h = 1; h < 24; h++) {
        expect(typical[h].left, greaterThan(typical[h - 1].right), reason: 'hours ${h - 1} and $h touch');
      }
      expect(typical.first.left, greaterThanOrEqualTo(20));
      expect(typical.last.right, lessThanOrEqualTo(370));
      // Bars share one baseline.
      for (final r in typical) {
        expect(r.bottom, closeTo(typical[12].bottom, 0.5));
      }
      // Nothing counted yet today before hour 3, so those hours have only the
      // typical bar; later hours with a count draw a today bar on the same
      // column, no wider than the typical one.
      for (var h = 3; h < 24; h++) {
        final today = find.byKey(ValueKey('occupancy-today-$h'));
        if (morning[h].today == 0) {
          expect(today, findsNothing);
        } else {
          final r = tester.getRect(today);
          expect(r.width, closeTo(typical[h].width, 0.5));
          expect(r.left, closeTo(typical[h].left, 0.5));
          expect(r.height, lessThanOrEqualTo(typical[h].height + 0.5));
        }
      }
    });
  }

  testWidgets('today bars have a width too, on the typical bar column', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(OccupancyChart(hourly: _openDay(), nowHour: 12), AppScheme.espresso));
    for (var h = 7; h <= 12; h++) {
      final today = tester.getRect(find.byKey(ValueKey('occupancy-today-$h')));
      final typical = tester.getRect(find.byKey(ValueKey('occupancy-typical-$h')));
      expect(today.width, greaterThanOrEqualTo(4), reason: 'hour $h');
      expect(today.left, closeTo(typical.left, 0.5));
      expect(today.bottom, closeTo(typical.bottom, 0.5));
    }
    expect(find.byKey(const ValueKey('occupancy-today-13')), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final open in [false, true]) {
      final name = 'occupancy_sheet_390x844_${open ? 'open' : 'closed'}_${brightness.name}';
      goldenWidgets(name, (tester) async {
        RitClock.pin(DateTime.utc(2026, 10, 14, 16));
        addTearDown(RitClock.reset);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final scheme = SchemeController.builtIn(brightness);
        final theme = AppTheme.from(scheme);
        final history = {
          'mdo_id': 123,
          'count': 4,
          'max_occ': 150,
          'open_status': open ? 'Open Now' : 'Closed Now',
          'hourly': [
            for (final h in open ? _openDay() : _real())
              {'hour': h.hour, 'today': h.today, 'one_week_ago': h.oneWeekAgo, 'average': h.average},
          ],
        };
        final location = DiningLocation.fromJson({
          // not 1: the response cache is shared, and the failure test below
          // needs an id with nothing stored
          'id': 2,
          'name': 'The Cafe & Market at Crossroads',
          'today': <dynamic>[],
          'is_open': open,
          'occupancy': {'count': 4, 'max_occ': 150},
        });
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: AppTheme.fontFamily)),
            home: Scaffold(
              backgroundColor: scheme.surface,
              body: DiningDetailSheet(
                location: location,
                api: ApiClient(backend: _Backend(history)),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('How busy'), findsOneWidget);
        expect(find.byKey(const ValueKey('occupancy-typical-12')), findsOneWidget);
        expect(
          find.textContaining(open ? 'usual for this time' : 'Closed now'),
          findsOneWidget,
        );
        await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name.png'));
      });
    }
  }

  testWidgets('no data at all is an unavailable state, not a blank block', (tester) async {
    final zeros = [
      for (var h = 0; h < 24; h++)
        OccupancyHour(hour: h, today: 0, oneWeekAgo: 0, average: 0),
    ];
    await tester.pumpWidget(_wrap(OccupancyChart(hourly: zeros, nowHour: 12), AppScheme.espresso));
    expect(find.text('Occupancy unavailable'), findsOneWidget);
    await tester.pumpWidget(_wrap(const OccupancyChart(hourly: [], nowHour: 12), AppScheme.espresso));
    expect(find.text('Occupancy unavailable'), findsOneWidget);
  });

  testWidgets('sheet says unavailable when the history fetch fails', (tester) async {
    final location = DiningLocation.fromJson({
      'id': 1,
      'name': 'Cafe',
      'today': <dynamic>[],
      'is_open': true,
      'occupancy': {'count': 4, 'max_occ': 150},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiningDetailSheet(
            location: location,
            api: ApiClient(backend: _Backend(StateError('down'))),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Occupancy unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading occupancy'), findsNothing);
  });
}
