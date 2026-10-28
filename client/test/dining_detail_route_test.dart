/// Opening a dining location must never trap the user.
///
/// The detail used to be a full height modal sheet whose only way out was a
/// drag handle under the status bar. With a long menu the barrier was covered
/// too, so nothing on screen closed it and iOS has no edge swipe for sheets.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  final location = DiningLocation.fromJson({
    'id': 1,
    'name': 'Gracies',
    'today': [
      {'opens_at': '2026-03-01T12:00:00Z', 'closes_at': '2026-03-01T23:00:00Z'},
    ],
    'is_open': true,
  });

  Future<void> open(
    WidgetTester tester, {
    required double width,
    required double scale,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    // notch and home indicator, as on a recent iPhone
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: DiningRow(
              location: location,
              api: ApiClient(backend: _MenuBackend()),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Gracies'));
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('detail has a visible back control at $width wide, ${scale}x text', (
        tester,
      ) async {
        await open(tester, width: width, scale: scale);

        final back = find.byTooltip('Back');
        expect(back, findsOneWidget);
        final box = tester.getRect(back);
        expect(box.top, greaterThanOrEqualTo(47), reason: 'not under the status bar');
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(width));
        expect(box.width, greaterThanOrEqualTo(40));

        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('Dish 0'), findsNothing);
        expect(find.byTooltip('Back'), findsNothing);
      });
    }
  }

  testWidgets('the app bar is titled with the location, so the route is announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, width: 390, scale: 1);

    final title = find.descendant(of: find.byType(AppBar), matching: find.text('Gracies'));
    expect(title, findsOneWidget);
    expect(
      tester.getSemantics(title),
      matchesSemantics(label: 'Gracies', namesRoute: true, isHeader: true),
    );
    // said once on screen, not again in the body
    expect(find.text('Gracies'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('detail shows the diet legend above the menu', (tester) async {
    await open(tester, width: 390, scale: 1);

    final legend = find.byKey(const ValueKey('diet-legend'));
    expect(legend, findsOneWidget);
    expect(
      tester.getTopLeft(legend).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('station-Grill'))).dy),
    );
  });

  testWidgets('iOS edge swipe closes the detail', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await open(tester, width: 390, scale: 1);
      expect(find.byTooltip('Back'), findsOneWidget);

      await tester.dragFrom(const Offset(2, 400), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('Gracies'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
