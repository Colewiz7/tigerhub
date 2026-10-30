/// Hiding Dorm side is about dining. Events held at those buildings must look
/// exactly the same with it hidden: the Events tab, Up next, club cards and the
/// pins and aliases on the map.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dashboard_event_cards.dart';
import 'package:tigerhub/cards/events_card.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/events_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/campus_event_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<CampusEvent> events;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await ResponseCache.instance.prune(olderThan: const Duration(days: -1));
    final groups = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
    StaticConfig.overrideForTesting({'dining_groups': groups});
    Preferences.instance.resetForTests();
    RitClock.pin(CampusTime.wall(2026, 10, 14, 12));
    final day = CampusTime.wallDate();
    DateTime at(int hour) => CampusTime.wall(day.year, day.month, day.day, hour);
    // held at the very buildings and venues the Dorm side switch covers
    events = [
      CampusEvent(
        uid: 'a',
        source: 'campusgroups',
        title: 'Open mic at Gracie\'s',
        startsAt: at(18),
        organizer: 'Music Program',
        organizerKey: 'MUSIC',
        location: "Gracie's",
        eventType: 'Social',
      ),
      CampusEvent(
        uid: 'b',
        source: 'campusgroups',
        title: 'Trivia at The Commons',
        startsAt: at(19),
        organizer: 'Robotics Club',
        organizerKey: 'ROBOTICS',
        location: 'The Commons',
        eventType: 'Social',
      ),
      CampusEvent(
        uid: 'c',
        source: 'campusgroups',
        title: 'Coffee hour at Beanz',
        startsAt: at(20),
        organizer: 'Robotics Club',
        organizerKey: 'ROBOTICS',
        location: 'Beanz',
        eventType: 'Social',
      ),
    ];
  });

  tearDown(() {
    RitClock.reset();
    Preferences.instance.resetForTests();
  });

  Result<Collection<CampusEvent>> result() => Result(value: Collection(data: events, stale: false), state: DataState.ok);

  // every string on screen, in order
  List<String> texts(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      text.data ?? text.textSpan?.toPlainText() ?? '',
  ];

  Future<List<String>> pumpSurface(WidgetTester tester, Widget surface, {required bool hidden}) async {
    await Preferences.instance.setGroupHidden('dorm_side', hidden);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(body: SingleChildScrollView(child: surface)),
      ),
    );
    await tester.pumpAndSettle();
    final seen = texts(tester);
    await tester.pumpWidget(const SizedBox());
    return seen;
  }

  Future<void> sameWithAndWithout(WidgetTester tester, Widget Function() surface) async {
    final shown = await pumpSurface(tester, surface(), hidden: false);
    final hidden = await pumpSurface(tester, surface(), hidden: true);
    expect(shown, isNotEmpty);
    expect(hidden, shown);
  }

  testWidgets('the Events tab is identical', (tester) async {
    await sameWithAndWithout(tester, () => SizedBox(height: 1500, child: EventsScreen(result: result())));
    final shown = await pumpSurface(tester, SizedBox(height: 1500, child: EventsScreen(result: result())), hidden: true);
    expect(shown, contains("Open mic at Gracie's"));
    expect(shown, contains('Trivia at The Commons'));
  });

  testWidgets('Up next is identical', (tester) async {
    await sameWithAndWithout(tester, () => EventsCard(result: result()));
  });

  testWidgets('a club card is identical', (tester) async {
    await sameWithAndWithout(tester, () => ScopedEventsCard(result: result(), organizerKey: 'ROBOTICS'));
  });

  test('event pins and aliases do not move', () {
    const features = [
      CampusMapFeature(
        id: 1,
        kind: 'water',
        kindName: 'Water fountains',
        name: 'fountain',
        geometryType: 'Point',
        coordinates: [
          [GeoCoordinate(-77.68, 43.08)],
        ],
        building: 'GWH',
      ),
    ];
    String summary() {
      final mapped = mapCampusEvents(events, features);
      return [
        for (final group in mapped.groups) '${group.building}:${group.events.map((e) => e.uid).join(',')}@${group.coordinate.longitude},${group.coordinate.latitude}',
        'unmapped ${mapped.unmapped}',
      ].join('|');
    }

    final before = summary();
    Preferences.instance.setGroupHidden('dorm_side', true);
    expect(summary(), before);
  });

  test('no event code reads the hidden groups', () {
    const eventFiles = [
      'lib/screens/events_screen.dart',
      'lib/cards/events_card.dart',
      'lib/cards/event_row.dart',
      'lib/cards/dashboard_event_cards.dart',
      'lib/data/event_aliases.dart',
      'lib/data/merge_events.dart',
      'lib/widgets/campus_event_mapper.dart',
      'lib/widgets/event_details_sheet.dart',
      'lib/services/event_filter.dart',
    ];
    for (final path in eventFiles) {
      final source = File(path).readAsStringSync();
      for (final word in ['hiddenDiningGroups', 'effectiveHidden', 'groupHiddenPlaces', 'withoutHiddenChefs', 'atHiddenPlace']) {
        expect(source, isNot(contains(word)), reason: '$path reads $word');
      }
    }
  });
}
