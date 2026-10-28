import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/empty_state.dart';
import 'package:tigerhub/widgets/status_row.dart';

class _DiningBackend implements Backend {
  _DiningBackend(this.features, {this.availability, this.failures = 0});

  final List<Map<String, dynamic>> features;
  final String? availability;

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
    throw UnimplementedError(path);
  }

  @override
  void close() {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpDining(
    WidgetTester tester,
    List<Map<String, dynamic>> features, {
    Size size = const Size(1000, 900),
    _DiningBackend? backend,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
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

  testWidgets('a quiet menu day explains itself without hiding locations', (
    tester,
  ) async {
    await pumpDining(tester, const []);

    expect(find.text('No menus published yet today'), findsOneWidget);
    expect(find.text('Crossroads'), findsOneWidget);
  });

  // 10 pm: TigerCenter loads with every menu empty
  testWidgets('loaded but empty is quiet text, no warning and no header', (
    tester,
  ) async {
    await pumpDining(tester, const [], backend: _DiningBackend(const [], availability: 'empty'));

    expect(find.text('No menus published yet today'), findsOneWidget);
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
    await tester.tap(find.text('No menus published yet today'));
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
}
