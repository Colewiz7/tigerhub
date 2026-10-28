/// Up next: the next few events that match your choices, soonest first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/events_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/status_row.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

// wed oct 14 2026 on campus, edt so utc is 4 hours ahead
DateTime _at(int hour, [int minute = 0]) => DateTime.utc(2026, 10, 14, hour + 4, minute);

CampusEvent _event(String uid, String title, int startHour, int endHour, {String org = 'Robotics Club', int startMinute = 0}) => CampusEvent(uid: uid, source: 'test', title: title, startsAt: _at(startHour, startMinute), endsAt: _at(endHour), organizer: org, organizerKey: org.toLowerCase());

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(_at(12));
  });

  tearDown(() async {
    RitClock.reset();
    await Preferences.instance.clearMutes();
    Preferences.instance.resetForTests();
  });

  Future<void> pumpToday(WidgetTester tester, List<CampusEvent> events) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 5000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok<DiningLocation>(const []),
          events: _ok(events),
          chefs: _ok<MenuItem>(const []),
          areas: _ok<HousingArea>(const []),
          onRefresh: () async {},
          onGoToTab: (_) {},
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Finder upNextCard() => find.ancestor(of: find.text('Up next'), matching: find.byType(EventsCard));

  List<String> rowTitles(WidgetTester tester) => [
    for (final row in tester.widgetList<StatusRow>(find.descendant(of: upNextCard(), matching: find.byType(StatusRow)))) row.title,
  ];

  group('the order', () {
    test('soonest first, a boost only breaks a tie', () {
      final a = _event('a', 'Alpha', 15, 16);
      final b = _event('b', 'Beta', 14, 15);
      final c = _event('c', 'Free pizza', 15, 16);
      final order = upNextOrder([a, b, c], boosted: {'c'}, now: _at(12));
      expect([for (final e in order) e.uid], ['b', 'c', 'a']);
    });

    test('a boosted later event does not jump an earlier one', () {
      final early = _event('early', 'Study hall', 13, 14);
      final late = _event('late', 'Free food', 18, 19);
      expect([for (final e in upNextOrder([late, early], boosted: {'late'}, now: _at(12))) e.uid], ['early', 'late']);
    });

    test('started and not over stays, ended goes, all day is not listed', () {
      final started = _event('started', 'Open lab', 11, 14);
      final ended = _event('ended', 'Morning run', 8, 9);
      final allDay = CampusEvent(uid: 'day', source: 'test', title: 'Art show', startsAt: DateTime.utc(2026, 10, 14, 4), allDay: true);
      expect([for (final e in upNextOrder([started, ended, allDay], now: _at(12))) e.uid], ['started']);
    });

    test('the hero counts today, all day included, never ended or tomorrow', () {
      final events = [
        _event('a', 'Open lab', 11, 14),
        _event('b', 'Morning run', 8, 9),
        CampusEvent(uid: 'day', source: 'test', title: 'Art show', startsAt: DateTime.utc(2026, 10, 14, 4), allDay: true),
        CampusEvent(uid: 'tomorrow', source: 'test', title: 'Later', startsAt: DateTime.utc(2026, 10, 15, 16), endsAt: DateTime.utc(2026, 10, 15, 17)),
        // last day of a multi day show
        CampusEvent(uid: 'expo', source: 'test', title: 'Expo', startsAt: DateTime.utc(2026, 10, 13, 4), endsAt: DateTime.utc(2026, 10, 15, 4), allDay: true),
      ];
      expect(upNextToday(events, now: _at(12)), 3);
    });
  });

  testWidgets('a phone shows Up next with flat rows in time order, at most 3, no organizer bars', (tester) async {
    await pumpToday(tester, [
      _event('d', 'Dance', 18, 19, org: 'Dance Club'),
      _event('a', 'Astronomy', 13, 14, org: 'Space Club'),
      _event('c', 'Coding', 16, 17, org: 'Robotics Club'),
      _event('b', 'Board games', 14, 15, org: 'Robotics Club'),
    ]);

    expect(find.text('Up next'), findsOneWidget);
    expect(rowTitles(tester), ['Astronomy', 'Board games', 'Coding']);
    expect(find.descendant(of: upNextCard(), matching: find.byType(GroupHeader)), findsNothing);
    expect(find.text('4 today'), findsOneWidget);
  });

  testWidgets('the hero counts what the filters leave', (tester) async {
    await Preferences.instance.setMuted('chess club', true);
    await pumpToday(tester, [
      _event('a', 'Astronomy', 13, 14, org: 'Space Club'),
      _event('b', 'Chess', 14, 15, org: 'Chess Club'),
    ]);
    expect(find.text('1 today'), findsOneWidget);
  });

  testWidgets('an event leaves Up next when it ends, with no new data', (tester) async {
    await pumpToday(tester, [
      _event('a', 'Astronomy', 12, 13, org: 'Space Club'),
      _event('b', 'Board games', 14, 15),
    ]);
    expect(rowTitles(tester), ['Astronomy', 'Board games']);

    RitClock.pin(_at(13, 1));
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(rowTitles(tester), ['Board games']);
    expect(find.text('1 today'), findsOneWidget);
  });

  testWidgets('from 600 wide the card keeps its name and organizer groups', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 5000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok<DiningLocation>(const []),
          events: _ok([_event('a', 'Astronomy', 13, 14, org: 'Space Club')]),
          chefs: _ok<MenuItem>(const []),
          areas: _ok<HousingArea>(const []),
          onRefresh: () async {},
          onGoToTab: (_) {},
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Up next'), findsNothing);
    expect(find.byType(GroupHeader), findsWidgets);
  });
}
