import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/empty_state.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

class _DiningBackend implements Backend {
  _DiningBackend(
    this.features, {
    this.availability,
    this.failures = 0,
    this.chefs,
  });

  final List<Map<String, dynamic>> features;
  final String? availability;

  // the chefs route answer, or a failed read when null
  final Map<String, dynamic>? chefs;

  // specials fetches that throw before one succeeds
  int failures;
  int specialsFetches = 0;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (path == '/dining/specials') {
      specialsFetches++;
      if (failures > 0) {
        failures--;
        throw const SocketException('offline');
      }
      return {'data': features, 'stale': false, 'last_updated': null, if (availability != null) 'availability': availability};
    }
    if (path == '/dining/visiting-chefs' && chefs != null) return chefs!;
    throw UnimplementedError(path);
  }

  @override
  void close() {}
}

Map<String, dynamic> _chef(int id, String name, {String? cuisine, String? place}) => {
  'id': id,
  'name': name,
  'cuisine': cuisine,
  'location_name': place ?? '',
  'start_time': '2026-10-14T15:00:00Z',
  'end_time': '2026-10-14T18:00:00Z',
};

Map<String, dynamic> _chefsBody(
  List<Map<String, dynamic>> data, {
  String availability = 'available',
}) => {
  'data': data,
  'stale': false,
  'last_updated': null,
  'availability': availability,
};

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // pinned to Wed Oct 14 2026 noon, the day the chef times are on
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });
  tearDown(RitClock.reset);
  // the cache singleton keeps its first store, so empty it between tests
  setUp(() => ResponseCache.instance.prune(olderThan: const Duration(days: -1)));

  Future<void> pumpDining(
    WidgetTester tester,
    List<Map<String, dynamic>> features, {
    Size size = const Size(1000, 900),
    _DiningBackend? backend,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.from(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFFF76902),
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: DiningScreen(
            api: ApiClient(backend: backend ?? _DiningBackend(features)),
            result: Result(
              value: Collection(
                data: const [
                  DiningLocation(
                    id: 23,
                    name: 'Crossroads',
                    category: 'food-court',
                    categoryName: 'Food courts',
                    isOpen: true,
                  ),
                  DiningLocation(
                    id: 24,
                    name: 'Midnight Oil',
                    category: 'coffee',
                    categoryName: 'Coffee',
                    isOpen: false,
                  ),
                ],
                stale: false,
              ),
              state: DataState.ok,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('visiting chefs group', () {
    final chefs = _chefsBody([
      _chef(1, 'Chef Marco', cuisine: 'Italian', place: 'Crossroads'),
      _chef(2, 'Chef Lin', cuisine: 'Sichuan', place: 'Gracie’s'),
    ]);

    testWidgets('lists each chef with cuisine, time and location above the menu', (tester) async {
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));

      expect(find.text('Visiting chefs'), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is GroupHeader && w.title == 'Visiting chefs'),
        findsNothing,
        reason: 'plain header, no filled bar',
      );
      expect(find.text('Chef Marco'), findsOneWidget);
      expect(find.text('Italian · 11 AM to 2 PM\nCrossroads'), findsOneWidget);
      expect(find.text('Sichuan · 11 AM to 2 PM\nGracie’s'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Chef Marco')).dy,
        lessThan(tester.getTopLeft(find.text('Menus not published yet today')).dy),
      );
    });

    testWidgets('drops a chef 30 minutes after the slot ends', (tester) async {
      RitClock.pin(DateTime.utc(2026, 10, 14, 18, 29, 59));
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
      expect(find.text('Chef Marco'), findsOneWidget);
    });

    testWidgets('hides the group once every chef has ended', (tester) async {
      RitClock.pin(DateTime.utc(2026, 10, 14, 18, 30));
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
      expect(find.text('Chef Marco'), findsNothing);
      expect(find.text('Visiting chefs'), findsNothing);
    });

    testWidgets('rows are labelled and at least 48pt tall', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));

      final row = find.byKey(const ValueKey('chef-1'));
      expect(
        tester.getSemantics(find.descendant(of: row, matching: find.byType(Semantics)).first).label,
        startsWith('Chef Marco, Italian · 11 AM to 2 PM\nCrossroads'),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    final hidden = <String, _DiningBackend>{
      'no chefs': _DiningBackend(const [], chefs: _chefsBody(const [])),
      'unavailable': _DiningBackend(const [], chefs: _chefsBody(const [], availability: 'unavailable')),
      'unavailable with rows': _DiningBackend(
        const [],
        chefs: _chefsBody([_chef(1, 'Chef Marco')], availability: 'unavailable'),
      ),
      'a failed read': _DiningBackend(const []),
    };
    for (final entry in hidden.entries) {
      testWidgets('is absent for ${entry.key}, with no warning', (tester) async {
        await pumpDining(tester, const [], backend: entry.value);

        expect(find.text('Visiting chefs'), findsNothing);
        expect(find.text('Chef Marco'), findsNothing);
        expect(find.textContaining('chefs'), findsNothing);
        expect(find.text('Crossroads'), findsOneWidget);
      });
    }

    testWidgets('a cached answer stays when the refresh fails', (tester) async {
      await ResponseCache.instance.write('/dining/visiting-chefs', chefs);
      await pumpDining(tester, const [], backend: _DiningBackend(const []));

      expect(find.text('Chef Marco'), findsOneWidget);
      expect(find.textContaining('Couldn’t'), findsNothing);
    });

  });

  testWidgets('published dining features appear with category and location', (
    tester,
  ) async {
    await pumpDining(tester, [
      {
        'id': 42,
        'name': 'Tomato bisque',
        'category': 'Soup',
        'location_name': 'Crossroads',
      },
    ]);

    expect(find.text('Tomato bisque'), findsOneWidget);
    expect(find.text('Soup · Crossroads'), findsOneWidget);
  });

  testWidgets('the quiet menu line says menus, not chefs', (tester) async {
    await pumpDining(tester, const []);

    expect(find.text('Menus not published yet today'), findsOneWidget);
    expect(find.textContaining(RegExp('^No ')), findsNothing);
  });

  testWidgets('a quiet menu day explains itself without hiding locations', (
    tester,
  ) async {
    await pumpDining(tester, const []);

    expect(find.text('Menus not published yet today'), findsOneWidget);
    expect(find.text('Crossroads'), findsOneWidget);
  });

  // 10 pm: TigerCenter loads with every menu empty
  testWidgets('loaded but empty is quiet text, no warning and no header', (
    tester,
  ) async {
    await pumpDining(tester, const [], backend: _DiningBackend(const [], availability: 'empty'));

    expect(find.text('Menus not published yet today'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byIcon(AppIconKind.sourceDown.of(tester.element(find.byType(DiningScreen)))), findsNothing);
    expect(find.text('Today’s published menu'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a source that never loaded says so and offers Retry', (
    tester,
  ) async {
    await pumpDining(tester, const [], backend: _DiningBackend(const [], availability: 'unavailable'));

    expect(find.text('Couldn’t load menus'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Today’s published menu'), findsNothing);
  });

  // the cache said empty, then the refresh failed: that is a failure, not a quiet day
  testWidgets('a cached empty menu with a failed refresh offers Retry, which works', (
    tester,
  ) async {
    await ResponseCache.instance.write('/dining/specials', {'data': <dynamic>[], 'stale': false, 'last_updated': null, 'availability': 'empty'});
    final backend = _DiningBackend(const [
      {'id': 42, 'name': 'Tomato bisque', 'category': 'Soup', 'location_name': 'Crossroads'},
    ], failures: 1);
    await pumpDining(tester, const [], backend: backend);

    expect(find.text('Couldn’t load menus'), findsOneWidget);
    expect(find.text('Menus not published yet today'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(backend.specialsFetches, 2);
    expect(find.text('Couldn’t load menus'), findsNothing);
    expect(find.text('Tomato bisque'), findsOneWidget);
  });

  testWidgets('a cached empty menu with a good refresh is the quiet line', (
    tester,
  ) async {
    await ResponseCache.instance.write('/dining/specials', {'data': <dynamic>[], 'stale': false, 'last_updated': null, 'availability': 'empty'});
    await pumpDining(tester, const [], backend: _DiningBackend(const [], availability: 'empty'));

    expect(find.text('Menus not published yet today'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  // menus in hand stay up when a refresh fails, no failure line over them
  testWidgets('cached menus stay when the refresh fails', (tester) async {
    await ResponseCache.instance.write('/dining/specials', {
      'data': [
        {'id': 42, 'name': 'Tomato bisque', 'category': 'Soup', 'location_name': 'Crossroads'},
      ],
      'stale': false,
      'last_updated': null,
    });
    await pumpDining(tester, const [], backend: _DiningBackend(const [], failures: 1));

    expect(find.text('Tomato bisque'), findsOneWidget);
    expect(find.text('Today’s published menu'), findsOneWidget);
    expect(find.text('Couldn’t load menus'), findsNothing);
  });

  testWidgets('a failed fetch offers Retry, which fetches again', (
    tester,
  ) async {
    final backend = _DiningBackend(const [
      {'id': 42, 'name': 'Tomato bisque', 'category': 'Soup', 'location_name': 'Crossroads'},
    ], failures: 1);
    await pumpDining(tester, const [], backend: backend);

    expect(find.text('Couldn’t load menus'), findsOneWidget);
    expect(find.text('Today’s published menu'), findsNothing);
    expect(backend.specialsFetches, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(backend.specialsFetches, 2);
    expect(find.text('Couldn’t load menus'), findsNothing);
    expect(find.text('Today’s published menu'), findsOneWidget);
    expect(find.text('Tomato bisque'), findsOneWidget);
  });

  testWidgets(
    'open filter removes closed locations and reports the result count',
    (tester) async {
      await pumpDining(tester, const []);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('1 place'), findsOneWidget);
      expect(find.text('Crossroads'), findsOneWidget);
      expect(find.text('Midnight Oil'), findsNothing);
    },
  );

  testWidgets('one search filters locations and the published menu', (
    tester,
  ) async {
    await pumpDining(tester, [
      {
        'id': 42,
        'name': 'Tomato bisque',
        'category': 'Soup',
        'location_name': 'Crossroads',
      },
    ]);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search dining or today’s menu'),
      'tomato',
    );
    await tester.pumpAndSettle();

    expect(find.text('Tomato bisque'), findsOneWidget);
    expect(find.text('Crossroads'), findsNothing);
    expect(find.text('No matching locations'), findsOneWidget);
  });

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    testWidgets('chips start on the content edge and the count has its own line at ${size.width.toInt()}', (tester) async {
      await pumpDining(tester, const [], size: size);

      final edge = tester.getRect(find.byType(StatusRow).first).left;
      final open = tester.getRect(find.widgetWithText(FilterChip, 'Open'));
      final pinned = tester.getRect(find.widgetWithText(FilterChip, 'Pinned'));
      final count = tester.getRect(find.text('2 places'));
      expect(open.left, edge);
      expect(count.left, edge);
      expect(count.top, greaterThanOrEqualTo(pinned.bottom));
    });
  }

  testWidgets('filters wrap cleanly on a phone-width screen', (tester) async {
    await pumpDining(tester, const [], size: const Size(360, 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('2 places'), findsOneWidget);
  });

  testWidgets('control F focuses and selects the dining search', (
    tester,
  ) async {
    await pumpDining(tester, const []);
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.tap(find.text('Menus not published yet today'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(
      field.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
  });

  final goldenChefs = _chefsBody([
    _chef(1, 'Chef Marco', cuisine: 'Italian', place: 'Crossroads'),
    _chef(2, 'Chef Lin', cuisine: 'Sichuan', place: 'Gracie’s'),
    _chef(3, 'Chef Amara Okonkwo-Reyes', cuisine: 'West African', place: 'Global Village Plaza'),
  ]);
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 2.0]) {
        final name = 'dining_chefs_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x';
        goldenWidgets(name, (tester) async {
          await pumpDining(
            tester,
            const [],
            size: size,
            brightness: brightness,
            scale: scale,
            backend: _DiningBackend(const [], chefs: goldenChefs),
          );
          expect(find.text('Chef Marco'), findsOneWidget);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name.png'));
        });
      }
    }
  }
}
