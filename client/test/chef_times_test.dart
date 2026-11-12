/// Every visiting chef row shows the time they are there, on the Today card,
/// the all-chefs sheet and the Dining group, at the two phone widths and both
/// text scales.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/chef_listing.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/rit_chefs.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/status_text.dart';

import 'golden_harness.dart';

// Wed Oct 14 2026: 11 AM and 2 PM on campus (EDT) are 15:00Z and 18:00Z
MenuItem _chef(
  int id,
  String name,
  String place, {
  int from = 15,
  int to = 18,
}) => MenuItem(
  id: id,
  locationName: place,
  name: name,
  startsAt: DateTime.utc(2026, 10, 14, from),
  endsAt: DateTime.utc(2026, 10, 14, to),
);

final _chefs = [
  _chef(1, 'Tandoor of India', 'The Cafe & Market at Crossroads'),
  _chef(2, "D'Mangu", 'Kitchen at Brick City'),
  _chef(3, 'Chef Marco', "Gracie's", from: 20, to: 23),
];

class _Backend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (path == '/dining/visiting-chefs') {
      return {
        'data': [
          for (final c in _chefs)
            {
              'id': c.id,
              'name': c.name,
              'location_name': c.locationName,
              'start_time': c.startsAt!.toIso8601String(),
              'end_time': c.endsAt!.toIso8601String(),
            },
        ],
        'stale': false,
        'last_updated': null,
        'availability': 'available',
      };
    }
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget body, {
  required double width,
  required double scale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

// the time pill of each row: whole on screen and on one line
void _expectTimes(WidgetTester tester, Finder within, int count, double width) {
  final pills = find.descendant(of: within, matching: find.byType(StatusText));
  final times = pills
      .evaluate()
      .where((e) => (e.widget as StatusText).text.contains(' to '))
      .toList();
  expect(times.length, count);
  for (final e in times) {
    final rect = tester.getRect(find.byWidget(e.widget));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
    expect(rect.height, lessThan(40 * 2), reason: 'one line');
  }
}

void main() {
  setUpAll(loadGoldenFonts);
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });
  tearDown(RitClock.reset);

  for (final width in [390.0, 440.0]) {
    for (final scale in [1.0, 2.0]) {
      final label = '${width.toInt()} wide, ${scale}x';

      testWidgets('Today card shows every chef time, $label', (tester) async {
        await _pump(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: VisitingChefsCard(
              result: Result(
                value: Collection<MenuItem>(data: _chefs, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        // the card previews a few rows on a phone, then "+N more"
        final shown = find.byType(VisitingChefsCard);
        final rows = find.descendant(
          of: shown,
          matching: find.textContaining(' to '),
        );
        expect(rows, findsWidgets);
        _expectTimes(tester, shown, rows.evaluate().length, width);
        expect(
          find.descendant(of: shown, matching: find.text('11 AM to 2 PM')),
          findsWidgets,
        );
      });

      testWidgets('all-chefs sheet shows every chef time, $label', (
        tester,
      ) async {
        await _pump(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: VisitingChefsCard(
              result: Result(
                value: Collection<MenuItem>(data: _chefs, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        await tester.tap(
          find.text('Chef today').evaluate().isNotEmpty
              ? find.text('Chef today')
              : find.text('3 today'),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 visiting chefs today'), findsOneWidget);
        final sheet = find
            .ancestor(
              of: find.text('3 visiting chefs today'),
              matching: find.byType(Column),
            )
            .first;
        _expectTimes(tester, sheet, 3, width);
        expect(
          find.descendant(of: sheet, matching: find.text('4 PM to 7 PM')),
          findsOneWidget,
        );
      });

      testWidgets('Dining chefs group shows every chef time, $label', (
        tester,
      ) async {
        await _pump(
          tester,
          DiningScreen(
            api: ApiClient(backend: _Backend()),
            result: const Result(
              value: Collection<DiningLocation>(data: [], stale: false),
              state: DataState.ok,
            ),
          ),
          width: width,
          scale: scale,
        );
        for (final c in _chefs) {
          _expectTimes(tester, find.byKey(ValueKey('chef-${c.id}')), 1, width);
        }
      });
    }
  }

  group('next chef line', () {
    final day = DateTime.utc(2026, 10, 14);
    UpcomingChef next({DateTime? from, DateTime? to}) => UpcomingChef(
      date: DateTime.utc(2026, 10, 15),
      name: "D'Mangu",
      locationName: 'Crossroads',
      startsAt: from,
      endsAt: to,
    );

    test('carries the time when one is known', () {
      final line = nextChefLine(
        next(
          from: DateTime.utc(2026, 10, 15, 15),
          to: DateTime.utc(2026, 10, 15, 18),
        ),
        day,
      );
      expect(line, "Next: Tomorrow · D'Mangu · Crossroads · 11 AM to 2 PM");
    });

    test('has no time when none is known', () {
      expect(
        nextChefLine(next(), day),
        "Next: Tomorrow · D'Mangu · Crossroads",
      );
    });
  });

  group('next chef from the schedule', () {
    final now = DateTime.utc(2026, 10, 14, 16);
    Map<String, dynamic> rit({
      required List<Map<String, dynamic>> today,
      required List<Map<String, dynamic>> tomorrow,
    }) => {
      'today': {'date': '2026-10-14', 'found': true, 'chefs': today},
      'today_ok': true,
      'schedule_ok': true,
      'schedule_at': '2026-10-14T11:00:00-04:00',
      'schedule': {
        '2026-10-14': {
          'empty': false,
          'unknown': false,
          'chefs': [
            for (final c in today)
              {'name': c['name'], 'location_name': c['location_name']},
          ],
        },
        '2026-10-15': {'empty': false, 'unknown': false, 'chefs': tomorrow},
      },
    };
    Map<String, dynamic> chef(
      String name,
      String place, {
      String start = '11:00',
      String end = '14:00',
    }) => {
      'name': name,
      'location_name': place,
      'location_id': 23,
      'start': start,
      'end': end,
    };

    test("takes today's time when the same chef is at the same place", () {
      final view = visitingChefsView(
        tigerCenter: null,
        rit: rit(
          today: [chef("D'Mangu", 'The Cafe & Market at Crossroads')],
          tomorrow: [
            {
              'name': "D'Mangu",
              'location_name': 'The Cafe & Market at Crossroads',
            },
          ],
        ),
        now: now,
      );
      final next = view['next'] as Map<String, dynamic>;
      expect(next['start_time'], isNotNull);
      expect(
        UpcomingChef.fromJson(next)!.startsAt!.toUtc(),
        DateTime.utc(2026, 10, 15, 15),
      );
      expect(
        UpcomingChef.fromJson(next)!.endsAt!.toUtc(),
        DateTime.utc(2026, 10, 15, 18),
      );
    });

    test('invents nothing for a different place', () {
      final view = visitingChefsView(
        tigerCenter: null,
        rit: rit(
          today: [chef("D'Mangu", 'Kitchen at Brick City')],
          tomorrow: [
            {
              'name': "D'Mangu",
              'location_name': 'The Cafe & Market at Crossroads',
            },
          ],
        ),
        now: now,
      );
      final next = UpcomingChef.fromJson(view['next'])!;
      expect(next.startsAt, isNull);
      expect(next.endsAt, isNull);
    });
  });
}
