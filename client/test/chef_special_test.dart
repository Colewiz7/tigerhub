/// A counter named like "Chef's Creation" leads the menu as "Chef's special".
///
/// FD files Crossroads' daily special under the counter "Chef's Creation"
/// (conceptData row 3, verified live 2026-11-03), not under a category, so the
/// parser carries each recipe's counter and the menu pulls those dishes up.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/sources/fd_menus.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/menu_section.dart';

Dish _dish(String name, {String? category, String? station, List<String> diet = const []}) =>
    Dish(name: name, category: category, station: station, dietary: diet);

MenuDay _menu(List<Dish> dishes) =>
    MenuDay(locationId: 23, serviceDate: DateTime(2026, 11, 3), dishes: dishes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
  });

  group('parser', () {
    final payload = jsonDecode(File('test/fixtures/fd_crossroads_2026-11-03.json').readAsStringSync()) as Map<String, dynamic>;

    test("stamps each dish with its counter from the fixture", () {
      final dishes = parseFdMenus(payload, mealPeriod: 'Lunch');
      String? station(String name) => dishes.firstWhere((d) => d['name'] == name)['station'] as String?;

      expect(station('Pork & Beef Bolognese'), "Chef's Creation");
      expect(station('Garlic Knot'), "Chef's Creation");
      expect(station('Vegan Bolognese w/ Tree Nuts'), "Chef's Creation");
      expect(station('Halal Burger'), 'Grill');
      expect(station('Lobster Bisque (7.5 Ounce)'), 'Soup');
    });

    test('the station survives into the dishes a location shows', () {
      final snapshot = {'dishes': parseFdMenus(payload, mealPeriod: 'Lunch')};
      final shown = dishesOn(snapshot, '2026-11-03');
      final special = shown.where((d) => d['station'] == "Chef's Creation");
      expect(special.map((d) => d['name']), containsAll(['Garlic Knot', 'Pork & Beef Bolognese']));
      expect(Dish.fromJson(special.first).station, "Chef's Creation");
    });
  });

  group('classifier', () {
    test('matches the real counter name in any case, and other special names', () {
      for (final name in ["Chef's Creation", "CHEFS CREATION", 'chef’s creation', 'Chef Specials', "Today's special"]) {
        expect(MenuSection.isSpecialStation(name), isTrue, reason: name);
      }
      for (final name in ['Grill', 'Entree', 'Soup', '']) {
        expect(MenuSection.isSpecialStation(name), isFalse, reason: name);
      }
    });

    test('a dish counts only by its counter, never its food type', () {
      expect(MenuSection.isChefSpecial(_dish('A', station: "Chef's Creation")), isTrue);
      expect(MenuSection.isChefSpecial(_dish('A', category: "Chef's Creation")), isFalse);
      expect(MenuSection.isChefSpecial(_dish('A')), isFalse);
    });
  });

  group('menu', () {
    Future<void> pump(WidgetTester tester, MenuDay menu) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
          home: Scaffold(
            body: SingleChildScrollView(child: MenuSection(menu: menu, prefs: Preferences.instance)),
          ),
        ),
      );
    }

    final header = find.byKey(const ValueKey('station-$chefSpecialTitle'));

    testWidgets("leads with an open Chef's special section holding its dishes", (tester) async {
      await pump(tester, _menu([
        _dish('Burger', category: 'Entree', station: 'Grill'),
        _dish('Garlic Knot', category: 'Side', station: "Chef's Creation", diet: ['Vegetarian']),
        _dish('Vegan Bolognese', category: 'Entree', station: "Chef's Creation", diet: ['Vegan', 'Vegetarian']),
      ]));

      expect(find.text("Chef's special"), findsOneWidget);
      expect(find.text('Garlic Knot'), findsOneWidget);
      expect(find.text('Vegan Bolognese'), findsOneWidget);
      expect(find.byKey(const ValueKey('diet-label-Vegan')), findsOneWidget);
      expect(find.text('Burger'), findsOneWidget);
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('station-Entree'))).dy),
      );
      // the dish is listed once, not again under its food type
      expect(find.byKey(const ValueKey('dish-Garlic Knot')), findsOneWidget);
    });

    testWidgets('no section when the feed names no chef special', (tester) async {
      await pump(tester, _menu([
        _dish('Burger', category: 'Entree', station: 'Grill'),
        _dish('Pizza', category: 'Pizzas', station: 'Pizza'),
      ]));

      expect(find.text("Chef's special"), findsNothing);
      expect(header, findsNothing);
      expect(find.text('Burger'), findsOneWidget);
    });
  });
}
