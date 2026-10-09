/// Event row day label and the /events start window follow the campus clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _RecordingBackend implements Backend {
  Map<String, String>? eventsQuery;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (path == '/events') eventsQuery = query;
    return {'items': <dynamic>[]};
  }

  @override
  void close() {}
}

// 10 PM PDT on 8 Oct is 1 AM EDT on 9 Oct
final _tenPmPacific = DateTime.utc(2026, 10, 9, 5);

Widget _row(CampusEvent event, {DateTime? now}) => MaterialApp(
  theme: AppTheme.from(ColorScheme.fromSeed(seedColor: Colors.orange)),
  home: Scaffold(
    body: EventRow(event: event, now: now),
  ),
);

CampusEvent _event(DateTime start) =>
    CampusEvent(uid: 'u', source: 'test', title: 'Dodgeball', startsAt: start);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(RitClock.reset);

  group('event row same day check', () {
    testWidgets('10 PM Pacific on 8 Oct is already 9 Oct on campus', (
      tester,
    ) async {
      RitClock.pin(_tenPmPacific);
      await tester.pumpWidget(_row(_event(CampusTime.wall(2026, 10, 9, 9))));
      expect(find.text('9:00 AM'), findsOneWidget);
      // only the subtitle carries the day, the trailing stamp is the clock
      expect(find.text('Fri 9 Oct, 9:00 AM'), findsOneWidget);
    });

    testWidgets('the injected moment is read on the campus clock', (
      tester,
    ) async {
      await tester.pumpWidget(
        _row(_event(CampusTime.wall(2026, 10, 9, 9)), now: _tenPmPacific),
      );
      expect(find.text('9:00 AM'), findsOneWidget);
    });

    testWidgets('a different campus day still shows the day', (tester) async {
      RitClock.pin(_tenPmPacific);
      await tester.pumpWidget(_row(_event(CampusTime.wall(2026, 10, 10, 9))));
      expect(find.text('Sat 10 Oct, 9:00 AM'), findsNWidgets(2));
    });

    testWidgets('late evening campus time is not tomorrow in UTC', (
      tester,
    ) async {
      // 11 PM EDT on 8 Oct is 03:00 UTC on 9 Oct
      RitClock.pin(CampusTime.wall(2026, 10, 8, 23));
      await tester.pumpWidget(_row(_event(CampusTime.wall(2026, 10, 8, 20))));
      expect(find.text('8:00 PM'), findsOneWidget);
    });
  });

  group('events start window', () {
    test('starts at campus midnight with the campus offset', () async {
      RitClock.pin(_tenPmPacific);
      final backend = _RecordingBackend();
      await ApiClient(backend: backend).events().toList();
      expect(backend.eventsQuery!['start'], '2026-10-09T00:00:00-04:00');
    });

    test('uses the standard offset in winter', () async {
      RitClock.pin(DateTime.utc(2026, 12, 15, 3));
      final backend = _RecordingBackend();
      await ApiClient(backend: backend).events().toList();
      expect(backend.eventsQuery!['start'], '2026-12-14T00:00:00-05:00');
    });
  });
}
