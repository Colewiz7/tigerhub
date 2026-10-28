/// Today shows what is still ahead: an event that has ended drops off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    // wed oct 14 2026, noon on campus
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(RitClock.reset);

  Future<void> pumpToday(WidgetTester tester, List<CampusEvent> events) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 5000);
    addTearDown(tester.view.reset);

    // a fresh tree, so each clock pin is read from scratch
    await tester.pumpWidget(const SizedBox());
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

  testWidgets('an ended event is gone from Today, an upcoming one stays', (tester) async {
    await pumpToday(tester, [
      CampusEvent(uid: 'old', source: 'test', title: 'Morning yoga', startsAt: DateTime.utc(2026, 10, 14, 12), endsAt: DateTime.utc(2026, 10, 14, 13), organizer: 'Rec', organizerKey: 'rec'),
      CampusEvent(uid: 'new', source: 'test', title: 'Robot build night', startsAt: DateTime.utc(2026, 10, 14, 22), endsAt: DateTime.utc(2026, 10, 14, 23), organizer: 'Robotics Club', organizerKey: 'robotics'),
    ]);

    expect(find.text('Robot build night'), findsWidgets);
    expect(find.text('Morning yoga'), findsNothing);
    expect(find.text('Ended'), findsNothing);
  });

  // campus midnight oct 14 is 04:00 utc, oct 15 is 04:00 utc the next day.
  // every instant here is utc, so the result is the same in any device zone
  final allDay = CampusEvent(uid: 'fair', source: 'drupal', title: 'Homecoming fair', startsAt: DateTime.utc(2026, 10, 14, 4), allDay: true, organizer: 'RIT', organizerKey: 'rit');
  final open = CampusEvent(uid: 'talk', source: 'test', title: 'Open studio', startsAt: DateTime.utc(2026, 10, 14, 15), organizer: 'Art Club', organizerKey: 'art');
  final multi = CampusEvent(uid: 'expo', source: 'campusgroups', title: 'Art expo', startsAt: DateTime.utc(2026, 10, 13, 4), endsAt: DateTime.utc(2026, 10, 15, 4), allDay: true, organizer: 'Gallery', organizerKey: 'gallery');

  final days = {
    'just after campus midnight': (DateTime.utc(2026, 10, 14, 4, 1), true),
    'campus noon': (DateTime.utc(2026, 10, 14, 16), true),
    'a minute before campus midnight': (DateTime.utc(2026, 10, 15, 3, 59), true),
    'the next campus day': (DateTime.utc(2026, 10, 15, 4, 1), false),
  };
  for (final MapEntry(key: moment, value: (now, shown)) in days.entries) {
    testWidgets('with no end, an all day event, a timed one and the last day of a multi day one ${shown ? 'show' : 'are gone'} $moment', (tester) async {
      RitClock.pin(now);
      // one at a time, the card folds a third organizer into "+1 organizers"
      for (final event in [allDay, open, multi]) {
        await pumpToday(tester, [event]);
        expect(find.text(event.title), shown ? findsWidgets : findsNothing, reason: event.title);
        expect(find.text('Ended'), findsNothing);
      }
    });
  }

  testWidgets('a timed event with no end has not started yet before its start', (tester) async {
    RitClock.pin(DateTime.utc(2026, 10, 14, 12));
    await pumpToday(tester, [open]);
    expect(find.text('Open studio'), findsWidgets);
  });
}
