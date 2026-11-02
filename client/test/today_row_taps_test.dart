/// Tapping a place or a chef on a Today card opens its detail, as in Dining.
/// Editing the card leaves the rows inert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async => {};

  @override
  void close() {}
}

void main() {
  late ApiClient api;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
    api = ApiClient(backend: _EmptyBackend());
  });
  tearDown(() {
    RitClock.reset();
    Preferences.instance.resetForTests();
  });


  final chefs = Result<Collection<MenuItem>>(
    value: ChefCollection(
      data: [
        MenuItem(
          id: 1,
          name: 'KO-BQ',
          locationName: 'The Cafe & Market at Crossroads',
          category: 'Visiting Chef',
          startsAt: DateTime.parse('2026-10-14T11:00:00-04:00'),
          endsAt: DateTime.parse('2026-10-14T14:00:00-04:00'),
        ),
        MenuItem(
          id: 2,
          name: 'Tandoor of India',
          locationName: 'RITZ',
          category: 'Visiting Chef',
          startsAt: DateTime.parse('2026-10-14T16:00:00-04:00'),
          endsAt: DateTime.parse('2026-10-14T19:00:00-04:00'),
        ),
      ],
      stale: false,
      lastUpdated: DateTime.now(),
    ),
    state: DataState.ok,
  );

  final dining = Result<Collection<DiningLocation>>(
    value: Collection(data: [DiningLocation(id: 1, name: 'Gracies', isOpen: true)], stale: false),
    state: DataState.ok,
  );

  Future<void> pump(WidgetTester tester, Widget card) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ));
    await tester.pump();
  }

  testWidgets('a chef row opens the chefs sheet on that chef', (tester) async {
    await pump(tester, VisitingChefsCard(result: chefs));
    await tester.tap(find.text('Tandoor of India'));
    await tester.pumpAndSettle();
    expect(find.text('2 visiting chefs today'), findsOneWidget);
    final sheetRow = find.descendant(of: find.byType(ListView), matching: find.text('Tandoor of India'));
    expect(sheetRow, findsOneWidget);
    final material = tester.widget<Material>(find.ancestor(of: sheetRow, matching: find.byType(Material)).first);
    expect((material.shape as RoundedRectangleBorder).side.width, 2);
  });

  testWidgets('a chef row is inert while the card is edited', (tester) async {
    await pump(tester, VisitingChefsCard(result: chefs, dragHandle: const SizedBox(width: 48, height: 48)));
    await tester.tap(find.text('Tandoor of India'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('2 visiting chefs today'), findsNothing);
  });

  testWidgets('a place row opens the dining detail', (tester) async {
    await pump(tester, DiningCard(result: dining, api: api));
    await tester.tap(find.text('Gracies'));
    await tester.pumpAndSettle();
    expect(find.byType(DiningCard), findsNothing, reason: 'the detail page covers the card');
  });

  testWidgets('a place row is inert while the card is edited', (tester) async {
    await pump(tester, DiningCard(result: dining, api: api, dragHandle: const SizedBox(width: 48, height: 48)));
    await tester.tap(find.text('Gracies'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(DiningCard), findsOneWidget);
  });
}
