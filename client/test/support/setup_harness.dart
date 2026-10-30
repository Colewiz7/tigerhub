/// Shared setup for the setup flow tests: real dining groups, bundled-style
/// housing areas, a few places and events.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/setup/setup_flow.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

const setupAreas = [
  HousingArea(id: 'residence-halls', name: 'Residence Halls', line2Example: 'Peterson 1234'),
  HousingArea(id: 'global-village', name: 'Global Village', line2Example: 'GV 400 1020'),
  HousingArea(id: 'rit-inn', name: 'RIT Inn', directDelivery: true),
];

List<DiningLocation> setupDining() => [
  const DiningLocation(id: 21, name: "Gracie's", isOpen: true),
  const DiningLocation(id: 31, name: 'Beanz', isOpen: true),
  const DiningLocation(id: 27, name: 'Corner Store', isOpen: true),
  const DiningLocation(id: 23, name: 'The Cafe & Market at Crossroads', isOpen: true),
  const DiningLocation(id: 32, name: "Ben and Jerry's", isOpen: false),
  const DiningLocation(id: 481, name: 'Bytes', isOpen: false),
];

List<CampusEvent> setupEvents() => [
  CampusEvent(
    uid: 'e1',
    source: 'test',
    title: 'Chess night',
    startsAt: DateTime.utc(2026, 10, 14, 23),
    organizer: 'Chess Club',
    organizerKey: 'chess',
  ),
  CampusEvent(
    uid: 'e2',
    source: 'test',
    title: 'Open mic',
    startsAt: DateTime.utc(2026, 10, 15, 23),
    organizer: 'Student Government',
    organizerKey: 'sg',
  ),
];

const _storedKeys = [
  'housing_area',
  'housing_unit',
  'dashboard_v2',
  'cards',
  'cards_hidden',
  'color_scheme',
  'pinned_dining',
  'hidden_dining',
  'hidden_dining_groups',
  'dining_layout',
  'muted_organizers',
  'hide_keywords',
  'boost_keywords',
  'keyword_rules_enabled',
  'setup_seen',
];

// the cache keeps the first platform it saw, so keys are emptied by hand
Future<void> resetSetupStorage() async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  for (final key in _storedKeys) {
    await ResponseCache.instance.writeOrder(key, const []);
  }
  final groups = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
  StaticConfig.overrideForTesting({'dining_groups': groups});
  Preferences.instance.resetForTests();
  await Preferences.instance.load();
}

class SetupHarness {
  SetupHarness(this.scheme);

  final SchemeController scheme;
  int done = 0;
  int cancelled = 0;
}

Future<SetupHarness> pumpSetup(
  WidgetTester tester, {
  bool rerun = false,
  Size size = const Size(390, 844),
  double scale = 1,
  double pixelRatio = 1,
  List<HousingArea> areas = setupAreas,
  List<DiningLocation>? dining,
  List<CampusEvent>? events,
  List<CardInstance> dashboard = defaultDashboard,
  AppScheme initial = AppScheme.espresso,
}) async {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = size * pixelRatio;
  addTearDown(tester.view.reset);
  final harness = SetupHarness(SchemeController(initial: initial));
  addTearDown(harness.scheme.dispose);
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: harness.scheme,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.from(harness.scheme.scheme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SetupFlow(
          scheme: harness.scheme,
          areas: areas,
          dining: dining ?? setupDining(),
          events: events ?? setupEvents(),
          dashboard: dashboard,
          rerun: rerun,
          onDone: () => harness.done++,
          onCancel: () => harness.cancelled++,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}
