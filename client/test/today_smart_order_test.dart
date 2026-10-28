/// Smart order: off by default. When on, Eat now rises at meal times and Up
/// next in the hour before an event. It never changes the saved order and
/// never applies in edit mode.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/settings/today_section.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/services/smart_order.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

const _saved = [
  CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
];

// wed oct 14 2026 on campus
DateTime _wall(int h, [int m = 0]) => CampusTime.wall(2026, 10, 14, h, m);

CampusEvent _talk(int h, int m) => CampusEvent(uid: 'talk', source: 'test', title: 'Robot talk', startsAt: _wall(h, m), endsAt: _wall(h + 1, m), organizer: 'Robotics Club', organizerKey: 'robotics');

void main() {
  group('the rule', () {
    List<String> ids(List<CardInstance> cards) => [for (final c in cards) c.id];

    test('eat now rises at breakfast, lunch and dinner only', () {
      for (final (minute, lifted) in [(7 * 60, true), (9 * 60 + 29, true), (9 * 60 + 30, false), (12 * 60, true), (15 * 60, false), (18 * 60, true), (19 * 60 + 30, false)]) {
        final order = ids(smartOrder(_saved, wallMinute: minute, eventSoon: false));
        expect(order.first == 'dining-0', lifted, reason: '$minute');
      }
    });

    test('up next rises when an event is within the hour, above eat now', () {
      expect(ids(smartOrder(_saved, wallMinute: 15 * 60, eventSoon: true)), ['events-0', 'chefs-0', 'dining-0']);
      expect(ids(smartOrder(_saved, wallMinute: 12 * 60, eventSoon: true)), ['events-0', 'dining-0', 'chefs-0']);
    });

    test('only the first card of a type moves', () {
      const second = CardInstance(id: 'dining-1', type: ModuleType.diningStatus);
      expect(ids(smartOrder([..._saved, second], wallMinute: 12 * 60, eventSoon: false)), ['dining-0', 'chefs-0', 'events-0', 'dining-1']);
    });

    test('an event within the hour is timed and still ahead', () {
      expect(eventWithinHour([_talk(13, 30)], _wall(12, 45)), isTrue);
      expect(eventWithinHour([_talk(14, 0)], _wall(12, 45)), isFalse);
      expect(eventWithinHour([_talk(12, 0)], _wall(12, 45)), isFalse);
    });
  });

  group('on Today', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      Preferences.instance.resetForTests();
    });
    tearDown(() async {
      RitClock.reset();
      await Preferences.instance.setTodaySmartOrder(false);
      Preferences.instance.resetForTests();
    });

    Future<void> pumpToday(WidgetTester tester, {List<CampusEvent> events = const []}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 4000);
      addTearDown(tester.view.reset);
      await DashboardStore.save(_saved);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(
          body: HomeScreen(
            api: ApiClient(backend: _EmptyBackend()),
            dining: _ok(const [DiningLocation(id: 1, name: 'Crossroads', isOpen: true)]),
            events: _ok(events),
            chefs: _ok(const [MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A')]),
            areas: _ok<HousingArea>(const []),
            onRefresh: () async {},
            onGoToTab: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    String firstTitle(WidgetTester tester) {
      final shells = find.byType(CardShell);
      final tops = {for (final title in ['Visiting chefs', 'Up next', 'Eat now']) title: tester.getTopLeft(find.descendant(of: shells, matching: find.text(title))).dy};
      return (tops.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).first.key;
    }

    testWidgets('off by default, so noon keeps the saved order', (tester) async {
      RitClock.pin(_wall(12));
      await pumpToday(tester);
      expect(Preferences.instance.todaySmartOrder, isFalse);
      expect(firstTitle(tester), 'Visiting chefs');
    });

    testWidgets('on at noon puts Eat now first and saves nothing', (tester) async {
      RitClock.pin(_wall(12));
      await Preferences.instance.setTodaySmartOrder(true);
      await pumpToday(tester);
      expect(firstTitle(tester), 'Eat now');
      expect([for (final c in await DashboardStore.load()) c.id], ['chefs-0', 'events-0', 'dining-0']);
    });

    testWidgets('on at 12:45 with a 1:30 event puts Up next first', (tester) async {
      RitClock.pin(_wall(12, 45));
      await Preferences.instance.setTodaySmartOrder(true);
      await pumpToday(tester, events: [_talk(13, 30)]);
      expect(firstTitle(tester), 'Up next');
    });

    testWidgets('edit mode shows the saved order', (tester) async {
      RitClock.pin(_wall(12));
      await Preferences.instance.setTodaySmartOrder(true);
      await pumpToday(tester);
      expect(firstTitle(tester), 'Eat now');
      await tester.tap(find.text('Edit Today'));
      await tester.pumpAndSettle();
      expect(firstTitle(tester), 'Visiting chefs');
    });

    testWidgets('the Settings switch turns it on', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: const Scaffold(body: TodaySection()),
      ));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(Preferences.instance.todaySmartOrder, isTrue);
    });
  });
}
