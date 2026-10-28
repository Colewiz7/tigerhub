/// Dining lists visiting chefs, then today's trucks, then places, then upcoming
/// trucks. Chefs and trucks are what people look for first.
///
/// Its own file because the response cache is a process wide singleton.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';

class _Backend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    final now = CampusTime.format(DateTime.now().toUtc());
    switch (path) {
      case '/dining/visiting-chefs':
        return {
          'data': [
            {
              'id': 1,
              'name': 'Chef Marco',
              'cuisine': 'Italian',
              'location_name': 'Crossroads',
              'start_time': '2026-10-14T15:00:00Z',
              'end_time': '2026-10-14T18:00:00Z',
            },
          ],
          'stale': false,
          'last_updated': now,
          'availability': 'available',
        };
      case '/dining/food-trucks':
        return {
          'data': [
            {'name': 'Taco Truck', 'date': '2026-10-14', 'time_text': '11 AM to 2 PM'},
            {'name': 'Pie Truck', 'date': '2026-10-15', 'time_text': '11 AM to 2 PM'},
          ],
          'stale': false,
          'last_updated': now,
          'availability': 'available',
        };
      case '/dining/specials':
        return {
          'data': [
            {'id': 42, 'name': 'Tomato bisque', 'category': 'Soup', 'location_name': 'Elsewhere'},
          ],
          'stale': false,
          'last_updated': now,
          'availability': 'available',
        };
    }
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });
  tearDown(RitClock.reset);

  Future<void> pumpDining(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 4000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiningScreen(
            api: ApiClient(backend: _Backend()),
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

  double top(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    return tester.getTopLeft(finder).dy;
  }

  // Today's published menu sits after the trucks and before the places
  testWidgets('today’s published menu sits between the trucks and the places', (tester) async {
    await pumpDining(tester);

    final chef = top(tester, find.text('Chef Marco'));
    final truck = top(tester, find.text('Taco Truck'));
    final menu = top(tester, find.text('Tomato bisque'));
    final place = top(tester, find.text('Crossroads').last);
    final later = top(tester, find.text('Pie Truck'));
    expect(chef, lessThan(truck));
    expect(truck, lessThan(menu));
    expect(menu, lessThan(place));
    expect(place, lessThan(later));
  });

  testWidgets('chefs, then trucks today, then places, then upcoming trucks', (tester) async {
    await pumpDining(tester);

    final chef = top(tester, find.text('Chef Marco'));
    final truck = top(tester, find.text('Taco Truck'));
    final place = top(tester, find.text('Crossroads').last);
    final later = top(tester, find.text('Pie Truck'));
    expect(chef, lessThan(truck));
    expect(truck, lessThan(place));
    expect(place, lessThan(later));
  });
}
