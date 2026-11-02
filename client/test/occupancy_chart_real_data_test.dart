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
import 'package:tigerhub/data/sources/maps_occupancy.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/dining_detail_sheet.dart';
import 'package:tigerhub/widgets/occupancy_chart.dart';

List<OccupancyHour> _real() => OccupancyHistory.fromJson(
  parseOccupancy(
    File('test/fixtures/maps_occupancy_123.data').readAsStringSync(),
    123,
  )!,
).hourly;

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
      await tester.pumpWidget(_wrap(OccupancyChart(hourly: morning, nowHour: 12), scheme));
      // Nothing today yet, a typical day peaking at 67. The tallest bar must
      // be a real fraction of the 96px plot, not a sliver.
      final tallest = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .map((b) => b.heightFactor!)
          .reduce((a, b) => a > b ? a : b);
      expect(tallest, greaterThan(0.9));
      final heights = tester
          .renderObjectList<RenderBox>(find.byType(DecoratedBox))
          .map((b) => b.size.height);
      expect(heights.reduce((a, b) => a > b ? a : b), greaterThan(60));
      expect(find.byKey(const ValueKey('occupancy-unavailable')), findsNothing);
    });
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
