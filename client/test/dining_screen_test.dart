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

class _DiningBackend implements Backend {
  const _DiningBackend(this.features);

  final List<Map<String, dynamic>> features;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (path == '/dining/specials') {
      return {'data': features, 'stale': false, 'last_updated': null};
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
            api: ApiClient(backend: _DiningBackend(features)),
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

    expect(find.text('No menu features are published today'), findsOneWidget);
    expect(find.text('Crossroads'), findsOneWidget);
  });

  testWidgets(
    'open now removes closed locations and reports the result count',
    (tester) async {
      await pumpDining(tester, const []);

      await tester.tap(find.text('Open now'));
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
    expect(
      find.text('No dining locations match these filters'),
      findsOneWidget,
    );
  });

  testWidgets('filters wrap cleanly on a phone-width screen', (tester) async {
    await pumpDining(tester, const [], size: const Size(360, 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Open now'), findsOneWidget);
    expect(find.text('2 places'), findsOneWidget);
  });

  testWidgets('control F focuses and selects the dining search', (
    tester,
  ) async {
    await pumpDining(tester, const []);
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.tap(find.text('Today’s published menu'));
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
