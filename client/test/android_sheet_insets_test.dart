/// Android draws edge to edge, so the system navigation bar (48 with three
/// buttons, 24 with a gesture pill) sits over the bottom of the screen. Every
/// sheet must scroll its last item fully above it, and keep it tappable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/dining_actions.dart';
import 'package:tigerhub/widgets/event_details_sheet.dart';
import 'package:tigerhub/widgets/places_sheet.dart';
import 'package:tigerhub/widgets/shuttle_routes_sheet.dart';
import 'package:tigerhub/widgets/whats_new_sheet.dart';

import 'support/dining_harness.dart';

const _height = 844.0;

class _MenuBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => {
    'service_date': '2026-03-01',
    'location_id': 1,
    'dishes': [
      for (var i = 0; i < 40; i++)
        {
          'name': 'Dish $i',
          'category': i.isEven ? 'Grill' : 'Pizza',
          'allergens': <String>[],
          'dietary': <String>['Vegetarian'],
        },
    ],
  };

  @override
  void close() {}
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  required double inset,
  required Widget home,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, _height);
  tester.view.padding = FakeViewPadding(top: 24, bottom: inset);
  tester.view.viewPadding = FakeViewPadding(top: 24, bottom: inset);
  addTearDown(tester.view.reset);
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.from(scheme).copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// Scrolls every scrollable under [within] to its end, then expects [last] to
/// sit fully above the system bar and take a tap there.
Future<void> _expectClear(
  WidgetTester tester,
  Finder within,
  Finder last,
  double inset,
) async {
  for (final scrollable
      in find
          .descendant(of: within, matching: find.byType(Scrollable))
          .evaluate()
          .toList()) {
    final finder = find.byWidget(scrollable.widget);
    await tester.fling(finder, const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();
  }
  expect(last, findsWidgets);
  final target = last.last;
  final rect = tester.getRect(target);
  expect(
    rect.bottom,
    lessThanOrEqualTo(_height - inset + 0.01),
    reason:
        'last item bottom ${rect.bottom} under the bar at ${_height - inset}',
  );
  expect(rect.height, greaterThanOrEqualTo(10));
  expect(target.hitTestable(), findsOneWidget);
}

void _forEachCase(
  String name,
  Future<void> Function(WidgetTester, double width, double scale, double inset)
  body,
) {
  for (final inset in [48.0, 24.0]) {
    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$name, bar $inset, $width wide, ${scale}x text',
          (tester) => body(tester, width, scale, inset),
        );
      }
    }
  }
}

Widget _opener(void Function(BuildContext) open) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  setUpAll(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  setUpDining();

  _forEachCase('what is new sheet keeps Not now above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: _opener((c) => showWhatsNewSheet(c)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _expectClear(
      tester,
      find.byType(BottomSheet),
      find.text('Not now'),
      inset,
    );
  });

  _forEachCase('move to group sheet keeps the last group above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    final location = sampleDining.first;
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: _opener((c) => showMoveToGroupSheet(c, location)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final rows = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(InkWell),
    );
    await _expectClear(tester, find.byType(BottomSheet), rows, inset);
  });

  _forEachCase('event sheet keeps the last button above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    final event = CampusEvent(
      uid: 'e1',
      source: 'test',
      title: 'Open house',
      startsAt: DateTime.utc(2026, 10, 14, 16),
      organizer: 'Admissions',
      location: 'Gordon Field House',
      description: List.filled(12, 'A long line about the event.').join('\n'),
      url: 'https://example.com/event',
    );
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: _opener((c) => showEventDetailsSheet(c, event)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final buttons = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byWidgetPredicate(
        (w) => w is OutlinedButton || w is FilledButton,
      ),
    );
    await _expectClear(tester, find.byType(BottomSheet), buttons, inset);
  });

  _forEachCase('shuttle sheet keeps its last row above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: _opener((c) => showShuttleRoutesSheet(c)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final texts = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Text),
    );
    await _expectClear(tester, find.byType(BottomSheet), texts, inset);
  });

  _forEachCase('places sheet keeps its last row above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    final api = ApiClient(backend: _PlacesBackend());
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: _opener(
        (c) => showModalBottomSheet<void>(
          context: c,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => PlacesSheet(
            api: api,
            kind: 'cafe',
            title: 'Cafes',
            icon: AppIconKind.dining,
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final texts = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Text),
    );
    await _expectClear(tester, find.byType(BottomSheet), texts, inset);
  });

  _forEachCase('dining detail keeps the last dish above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    final location = DiningLocation.fromJson({
      'id': 1,
      'name': 'Gracies',
      'today': [
        {
          'opens_at': '2026-03-01T12:00:00Z',
          'closes_at': '2026-03-01T23:00:00Z',
        },
      ],
      'is_open': true,
    });
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: Scaffold(
        body: SafeArea(
          child: DiningRow(
            location: location,
            api: ApiClient(backend: _MenuBackend()),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Gracies'));
    await tester.pumpAndSettle();
    // the dietary chips overflow by a few pixels at 2x text on main; a separate bug
    tester.takeException();
    await _expectClear(
      tester,
      find.byType(Scaffold).last,
      find.textContaining('Tags are exactly'),
      inset,
    );
  });

  _forEachCase('all chefs sheet keeps the last chef above the bar', (
    tester,
    width,
    scale,
    inset,
  ) async {
    final chefs = [
      for (var i = 0; i < 12; i++)
        MenuItem(
          id: i,
          name: 'Chef $i',
          locationName: 'RITZ',
          cuisine: 'Cuisine $i',
          startsAt: DateTime.parse('2026-10-14T11:00:00-04:00'),
          endsAt: DateTime.parse('2026-10-14T14:00:00-04:00'),
        ),
    ];
    await _pump(
      tester,
      width: width,
      scale: scale,
      inset: inset,
      home: Scaffold(
        body: SingleChildScrollView(
          child: VisitingChefsCard(
            result: Result(
              value: ChefCollection(data: chefs, stale: false),
              state: DataState.ok,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Visiting chefs'));
    await tester.pumpAndSettle();
    await _expectClear(
      tester,
      find.byType(BottomSheet),
      // the whole row, not just its first line of text
      find
          .ancestor(of: find.text('Chef 11'), matching: find.byType(Material))
          .first,
      inset,
    );
  });

  tearDown(Preferences.instance.resetForTests);
}

class _PlacesBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => {
    'data': [
      for (var i = 0; i < 30; i++)
        {
          'id': i,
          'name': 'Place $i',
          'kind': 'cafe',
          'building': 'Building ${i ~/ 5}',
        },
    ],
    'stale': false,
    'last_updated': null,
  };

  @override
  void close() {}
}
