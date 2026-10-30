/// iOS screenshots for the ios-screens Codemagic workflow
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/config.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/screens/events_screen.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/screens/settings/settings_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/dining_detail_sheet.dart';
import 'package:tigerhub/widgets/phone_frame.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

import 'fixtures.g.dart';

// 12:30 edt on the day the fixtures were captured
final _now = DateTime.utc(2026, 8, 30, 16, 30);

// workflow runs one appearance per drive; every scheme is dark now
const _only = String.fromEnvironment('SCREENS_APPEARANCE');
final _appearances = [
  for (final b in [Brightness.dark])
    if (_only.isEmpty || b.name == _only) b,
];

// only the workflow answers the device shot lines
const _deviceShots = bool.fromEnvironment('DEVICE_SHOTS');

const _scrollBy = 600.0;
const _detailId = 23;
const _detailName = 'The Cafe & Market at Crossroads';

// the redesign's card set, not the shipped defaults
const _todayCards = [
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(id: 'shuttles-0', type: ModuleType.shuttles, size: CardSize.compact),
  CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs, size: CardSize.compact),
  CardInstance(id: 'facility-0', type: ModuleType.facilityHours, size: CardSize.compact, scope: 'Judson/Hale Aquatics Center'),
  CardInstance(id: 'package-0', type: ModuleType.packagePickup, size: CardSize.compact),
];

// global village home, crossroads pinned
Future<void> _seedToday() async {
  await Preferences.instance.setHome(area: 'global-village');
  if (!Preferences.instance.isPinned(_detailId)) await Preferences.instance.togglePinned(_detailId);
  await DashboardStore.save(_todayCards);
}

const _tabs = [
  ('today', HomeScreen),
  ('dining', DiningScreen),
  ('events', EventsScreen),
  ('map', MapScreen),
  ('campus', CampusScreen),
];

class _FixtureBackend implements Backend {
  late final _map = parseCampusMapFeatures(mapCategory35);

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async {
    switch (path) {
      case '/dining':
        return _openAt(_decode(diningJson), _now);
      case '/events':
        return _decode(eventsJson);
      case '/dining/visiting-chefs':
        return _decode(chefsJson);
      case '/dining/specials':
        return _decode(specialsJson);
      case '/dining/$_detailId/occupancy':
        return _decode(occupancy23Json);
      case '/dining/$_detailId/menu':
        return _menu;
      case '/housing/areas':
        return _decode(housingJson);
      case '/post-offices':
        return _decode(postOfficesJson);
      case '/recreation/hours':
        return _decode(recreationJson);
      case '/makerspace/hours':
        return {'items': jsonDecode(makerspaceHoursJson)};
      case '/makerspace/rooms':
        return _decode(makerspaceRoomsJson);
      case '/campus/places':
        return _decode(placeKindsJson);
      case '/campus/map':
        return {'data': _map, 'stale': false, 'last_updated': null};
    }
    // a saved home makes the housing card ask, and the empty fallback below is not an address
    if (path.endsWith('/address')) throw const SocketException('not in the fixtures');
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Map<String, dynamic> _decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;

// captured at 1:33am, so is_open says closed everywhere
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

// no captured menu exists, so a small made up one
final Map<String, dynamic> _menu = {
  'location_id': _detailId,
  'service_date': '2026-08-30',
  'dishes': [
    {'name': 'Grilled chicken sandwich', 'category': 'Grill', 'allergens': ['Wheat'], 'dietary': <String>[], 'calories': 520},
    {'name': 'Black bean burger', 'category': 'Grill', 'allergens': ['Soy', 'Wheat'], 'dietary': ['Vegan'], 'calories': 410},
    {'name': 'Tomato basil soup', 'category': 'Soup', 'allergens': ['Milk'], 'dietary': ['Vegetarian'], 'calories': 180},
    {'name': 'Caesar salad', 'category': 'Salad', 'allergens': ['Egg', 'Fish', 'Milk'], 'dietary': <String>[], 'calories': 320},
    {'name': 'Margherita flatbread', 'category': 'Pizza', 'allergens': ['Milk', 'Wheat'], 'dietary': ['Vegetarian'], 'calories': 640},
    {'name': 'Fruit cup', 'category': 'Grab and go', 'allergens': <String>[], 'dietary': ['Vegan'], 'calories': 90},
  ],
};

// mirrors main.dart, only the backend differs
Widget _app(ApiClient api, SchemeController scheme) => AnimatedBuilder(
  animation: scheme,
  builder: (context, _) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.from(scheme.scheme),
      builder: phoneModeBuilder(PhoneMode.fromEnvironment()),
      home: AppShell(api: api, scheme: scheme),
    );
  },
);

// asset loads and image decodes arent frames
Future<void> _settle(WidgetTester tester) async {
  const timeout = Duration(seconds: 15);
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, timeout);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, timeout);
}

// case blind, labels go sentence case soon
Finder _tab(String label) => find.descendant(of: find.byType(AppTabBar), matching: find.textContaining(RegExp('^$label\$', caseSensitive: false))).first;

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_tab(label));
  await _settle(tester);
}

// biggest onstage vertical scrollable under root
ScrollableState _mainScrollable(Finder root) {
  ScrollableState? best;
  var bestArea = 0.0;
  for (final element in find.descendant(of: root, matching: find.byType(Scrollable)).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    final size = element.size ?? Size.zero;
    if (state.position.axis == Axis.vertical && size.width * size.height > bestArea) {
      best = state;
      bestArea = size.width * size.height;
    }
  }
  return best ?? (throw StateError('no vertical scrollable under $root'));
}

// a real finger drag, held still before lifting so nothing flings
Future<void> _drag(WidgetTester tester, Finder target, Offset by) async {
  // a still finger is a tap
  if (by == Offset.zero) return;
  final gesture = await tester.startGesture(tester.getCenter(target));
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(by / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await _settle(tester);
}

Future<void> _toTop(WidgetTester tester, Finder root) async {
  _mainScrollable(root).position.jumpTo(0);
  await _settle(tester);
}

Future<void> _scrollDown(WidgetTester tester, Finder root) async {
  final scrollable = _mainScrollable(root);
  final distance = math.min(_scrollBy, scrollable.position.maxScrollExtent);
  // within slop it lands as a tap
  if (distance <= kTouchSlop) return;
  await _drag(tester, find.byWidget(scrollable.widget), Offset(0, -distance));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

  setUp(() => RitClock.pin(_now));
  tearDown(RitClock.reset);

  testWidgets('ios screens', (tester) async {
    // ios needs no convertFlutterSurfaceToImage, android only
    Future<void> shot(String name) async {
      await binding.takeScreenshot(name);
    }

    // every tab shot shows the bar, over scrolled content too
    Future<void> tabShot(String name) async {
      expect(find.byType(AppTabBar).hitTestable(), findsOneWidget, reason: 'no tab bar on top in $name');
      await shot(name);
    }

    // the workflow takes a simctl screenshot on this line, status bar and all
    Future<void> deviceShot(String name, Type screen) async {
      if (!_deviceShots) return;
      final tab = _tabs.indexWhere((t) => t.$2 == screen);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).index, tab, reason: 'wrong tab selected for $name');
      expect(find.byType(screen), findsOneWidget, reason: 'wrong screen for $name');
      // a fresh name, an old ack never counts
      final done = File('${Directory.systemTemp.path}/$name.${DateTime.now().microsecondsSinceEpoch}.done');
      debugPrint('device shot $name ${done.path}');
      // the log line lands seconds late, wait for the hosts ack
      final acked = await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!done.existsSync() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return done.existsSync();
      });
      // runAsync only logs a throw, this stops the run
      expect(acked, isTrue, reason: 'no device shot of $name');
    }

    // skips the first run setup screen
    await Preferences.instance.markSetupSeen();
    await _seedToday();
    final scheme = SchemeController()..load();
    addTearDown(scheme.dispose);
    await tester.pumpWidget(_app(ApiClient(backend: _FixtureBackend()), scheme));
    await _settle(tester);

    for (final appearance in _appearances) {
      await scheme.select(AppScheme.espresso);
      await _settle(tester);
      final mode = appearance.name;

      for (final (name, type) in _tabs) {
        await _openTab(tester, name);
        final root = find.byType(type);

        if (type == MapScreen) {
          await tester.tap(find.byTooltip('Fit campus'));
          await _settle(tester);
          await tabShot('map_${mode}_top');
          await deviceShot('map_${mode}_top', type);
          final viewer = find.descendant(of: root, matching: find.byType(InteractiveViewer));
          await _drag(tester, viewer, const Offset(-120, -160));
          await tabShot('map_${mode}_panned');
          continue;
        }

        await _toTop(tester, root);
        await tabShot('${name}_${mode}_top');
        await deviceShot('${name}_${mode}_top', type);
        await _scrollDown(tester, root);
        await tabShot('${name}_${mode}_scrolled');

        if (type == HomeScreen) {
          // edit mode, from the button at the end of the page
          final edit = find.text('Edit Today');
          await tester.scrollUntilVisible(edit, 300, scrollable: find.byWidget(_mainScrollable(root).widget));
          await tester.tap(edit);
          await _settle(tester);
          await _toTop(tester, root);
          await tabShot('${name}_${mode}_edit');
          await tester.scrollUntilVisible(find.text('Done'), 300, scrollable: find.byWidget(_mainScrollable(root).widget));
          await tester.tap(find.text('Done'));
          await _settle(tester);
        }

        if (type == DiningScreen) {
          await _toTop(tester, root);
          final row = find.descendant(of: root, matching: find.text(_detailName)).first;
          await tester.scrollUntilVisible(row, 200, scrollable: find.byWidget(_mainScrollable(root).widget));
          await tester.tap(row);
          await _settle(tester);
          final sheet = find.byType(DiningDetailSheet);
          await shot('dining_detail_${mode}_top');
          await _scrollDown(tester, sheet);
          await shot('dining_detail_${mode}_scrolled');
          Navigator.of(tester.element(sheet)).pop();
          await _settle(tester);
        }
      }

      // the gear moves to todays title row, so open it from there
      await _openTab(tester, 'today');
      await tester.tap(find.byTooltip('Settings'));
      await _settle(tester);
      final settings = find.byType(SettingsScreen);
      await _toTop(tester, settings);
      await shot('settings_${mode}_top');
      await _scrollDown(tester, settings);
      await shot('settings_${mode}_scrolled');
      await tester.tap(find.byTooltip('Close settings'));
      await _settle(tester);
    }

    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  // the workflow records the screen between the two log lines
  testWidgets('tab bar scrub', (tester) async {
    await Preferences.instance.markSetupSeen();
    final scheme = SchemeController();
    addTearDown(scheme.dispose);
    await tester.pumpWidget(_app(ApiClient(backend: _FixtureBackend()), scheme));
    await _settle(tester);

    final start = tester.getCenter(_tab('today'));
    final end = tester.getCenter(_tab('campus'));
    final back = tester.getCenter(_tab('dining'));
    debugPrint('tab scrub start');
    // recordVideo takes a moment to start
    await tester.pump(const Duration(milliseconds: 1500));

    final gesture = await tester.startGesture(start);
    var at = start.dx;
    // small steps, a finger never skips a tab
    Future<void> to(double x) async {
      while ((x - at).abs() > 5) {
        at += x > at ? 5 : -5;
        await gesture.moveTo(Offset(at, start.dy));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    await to(end.dx);
    await to(back.dx);
    await gesture.up();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
    debugPrint('tab scrub end');
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  }, skip: !_appearances.contains(Brightness.dark));
}
