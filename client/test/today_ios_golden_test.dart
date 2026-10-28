/// Today as the iOS screenshots seed it: home in Global Village, Crossroads
/// pinned, and the redesign's card set, on the captured fixtures at the same
/// moment. Lets the screen be reviewed without a simulator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/shuttles.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

import 'golden_harness.dart';

// sun aug 30 2026, 12:30 PM on campus, as the screenshots
final _now = DateTime.utc(2026, 8, 30, 16, 30);

const _cards = [
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(id: 'shuttles-0', type: ModuleType.shuttles, size: CardSize.compact),
  CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs, size: CardSize.compact),
  CardInstance(id: 'facility-0', type: ModuleType.facilityHours, size: CardSize.compact, scope: 'Judson/Hale Aquatics Center'),
  CardInstance(id: 'package-0', type: ModuleType.packagePickup, size: CardSize.compact),
];

Map<String, dynamic> _json(String name) => jsonDecode(File('test/golden/$name.json').readAsStringSync()) as Map<String, dynamic>;

// open and closed as of now, as the screenshot backend does
Map<String, dynamic> _openAt(Map<String, dynamic> body, DateTime now) {
  for (final loc in (body['data'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final spans = (loc['today'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final current = spans.where((s) => !now.isBefore(DateTime.parse(s['opens_at'] as String)) && now.isBefore(DateTime.parse(s['closes_at'] as String)));
    final next = spans.where((s) => now.isBefore(DateTime.parse(s['opens_at'] as String)));
    loc['is_open'] = current.isNotEmpty;
    loc['closes_at'] = current.isEmpty ? null : current.first['closes_at'];
    loc['opens_at'] = next.isEmpty ? null : next.first['opens_at'];
    loc['next_transition'] = loc['closes_at'] ?? loc['opens_at'];
  }
  return body;
}

class _FixtureBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async => switch (path) {
    '/dining' => _openAt(_json('dining'), _now),
    '/events' => _json('events'),
    '/dining/visiting-chefs' => _json('dining_visiting-chefs'),
    '/housing/areas' => _json('housing_areas'),
    '/post-offices' => _json('post-offices'),
    '/recreation/hours' => _json('recreation_hours'),
    '/makerspace/hours' => {'items': <dynamic>[]},
    // only the default set asks, before the saved one loads
    _ when path.endsWith('/address') => throw const SocketException('not in the fixtures'),
    _ => {'data': <dynamic>[], 'stale': false, 'last_updated': null},
  };

  @override
  void close() {}
}

void main() {
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(_now);
    ShuttleSchedule.overrideForTesting(ShuttleSchedule.parse(jsonDecode(File('assets/config/shuttles.json').readAsStringSync()) as Map<String, dynamic>));
    StaticConfig.overrideForTesting({
      for (final name in ['dining_categories', 'post_offices', 'housing_areas', 'shed_hours', 'fd_locations'])
        name: jsonDecode(File('assets/config/$name.json').readAsStringSync()) as Map<String, dynamic>,
    });
  });
  tearDown(() {
    RitClock.reset();
    ShuttleSchedule.overrideForTesting(null);
    Preferences.instance.resetForTests();
  });

  Future<void> pumpToday(WidgetTester tester, Size size, Brightness brightness, double scale) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await Preferences.instance.markSetupSeen();
    await Preferences.instance.setHome(area: 'global-village');
    await Preferences.instance.togglePinned(23);
    await DashboardStore.save(_cards);
    final scheme = SchemeController();
    addTearDown(scheme.dispose);
    await tester.pumpWidget(Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.from(SchemeController.builtIn(brightness)).copyWith(platform: TargetPlatform.iOS),
          home: AppShell(api: ApiClient(backend: _FixtureBackend()), scheme: scheme),
        ),
      ),
    ));
    // the mark decodes off the test clock
    final mark = tester.element(find.byType(AppShell));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/images/tigerhub-mascot.png'), mark));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 2.0]) {
        final name = 'today_ios_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x.png';
        goldenWidgets(name, (tester) async {
          await pumpToday(tester, size, brightness, scale);
          await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/$name'));
        });
      }
    }
  }

  goldenWidgets('today_ios_390x844_light_1x_scrolled.png', (tester) async {
    await pumpToday(tester, const Size(390, 844), Brightness.light, 1);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/today_ios_390x844_light_1x_scrolled.png'));
  });

  goldenWidgets('today_ios_390x844_light_1x_end.png', (tester) async {
    await pumpToday(tester, const Size(390, 844), Brightness.light, 1);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/today_ios_390x844_light_1x_end.png'));
  });
}
