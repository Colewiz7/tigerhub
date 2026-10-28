/// One icon per dining place, one per chef cuisine family.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/chef_family.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

final _places = [
  for (final p in (json.decode(File('assets/config/dining_groups.json').readAsStringSync())['places'] as List).cast<Map<String, dynamic>>()) (id: p['id'] as int, name: p['name'] as String),
];

MenuItem _chef(String name, [String? cuisine]) => MenuItem(id: 1, name: name, locationName: 'RITZ', cuisine: cuisine);

// the five chefs in rit_dining_menus.html
final _today = [
  _chef('KO-BQ', 'Korean fusion cuisine'),
  _chef('Tandoor of India', 'Traditional southern and northern Indian dishes'),
  _chef('P.H. Express', 'Traditional Pakistani cuisine'),
  _chef("D'Mangu", 'Native Dominican cuisine'),
  _chef('P.H. Express', 'Traditional Pakistani cuisine'),
];

void main() {
  setUpAll(loadGoldenFonts);

  test('each place id has its icon', () {
    expect(iconForPlace(21, "Gracie's").material, Icons.dinner_dining_rounded);
    expect(iconForPlace(22, 'Kitchen at Brick City').material, Icons.outdoor_grill_rounded);
    expect(iconForPlace(23, 'The Cafe & Market at Crossroads').material, Icons.restaurant_rounded);
    expect(iconForPlace(24, 'The Commons').material, Icons.lunch_dining_rounded);
    expect(iconForPlace(25, 'Patio at Global Village').material, Icons.deck_rounded);
    expect(iconForPlace(26, 'RITZ').material, Icons.sports_basketball_rounded);
    expect(iconForPlace(27, 'Corner Store').material, Icons.storefront_rounded);
    expect(iconForPlace(28, "Sol's Underground").material, Icons.local_grocery_store_rounded);
    expect(iconForPlace(29, 'The Market at Global Village').material, Icons.shopping_basket_rounded);
    expect(iconForPlace(30, 'Artesano Bakery & Cafe').material, Icons.bakery_dining_rounded);
    expect(iconForPlace(31, 'Beanz').material, Icons.coffee_rounded);
    expect(iconForPlace(32, "Ben and Jerry's").material, Icons.icecream_rounded);
    expect(iconForPlace(34, 'CTRL ALT DELi').material, Icons.keyboard_rounded);
    expect(iconForPlace(35, 'The College Grind').material, Icons.coffee_maker_rounded);
    expect(iconForPlace(36, "Nathan's Soup & Salad").material, Icons.soup_kitchen_rounded);
    expect(iconForPlace(37, "Java Wally's").material, Icons.local_cafe_rounded);
    expect(iconForPlace(38, 'Midnight Oil').material, Icons.bedtime_rounded);
    expect(iconForPlace(39, 'USB Ultimate Smoothie Blendz').material, Icons.blender_rounded);
    expect(iconForPlace(61, 'GPC Club Lounge').material, Icons.restaurant_menu_rounded);
    expect(iconForPlace(441, 'Loaded Latke').material, Icons.takeout_dining_rounded);
    expect(iconForPlace(461, 'Petals at RIT Inn').material, Icons.local_florist_rounded);
    expect(iconForPlace(481, 'Bytes Micro Market').material, Icons.memory_rounded);
  });

  test('the id decides, not the name', () {
    expect(iconForPlace(31, 'Anything'), AppIconKind.coffee);
    expect(iconForPlace(999, 'Dining Office'), AppIconKind.diningOffice);
  });

  test('unlisted places keep their venue icon', () {
    expect(iconForPlace(41, 'Dining Office'), AppIconKind.diningOffice);
    expect(iconForPlace(501, 'RIT Food Truck'), AppIconKind.truck);
  });

  test('place icons are distinct and rounded', () {
    final icons = [for (final p in _places) iconForPlace(p.id, p.name).material];
    final listed = [for (final p in _places) if (placeIcons.containsKey(p.id)) iconForPlace(p.id, p.name).material];
    expect(listed.toSet().length, listed.length);
    expect(icons.toSet().length, icons.length, reason: 'unlisted places differ too');
    expect(placeIcons.length, 22);
    for (final kind in placeIcons.values) {
      expect(kind.cupertino, kind.material, reason: kind.name);
      expect(AppIconKind.materialOnIos, contains(kind), reason: kind.name);
    }
  });

  test('every dining place is listed or knowingly left out', () {
    final missing = [for (final p in _places) if (!placeIcons.containsKey(p.id)) p.id];
    expect(missing, [41, 501]);
  });

  test('the type filter still reads the venue type', () {
    expect(iconForVenue('The Cafe & Market at Crossroads'), AppIconKind.diningHall);
    expect(iconForVenue('Beanz'), AppIconKind.cafe);
  });

  test('chef cuisine families pick their icon', () {
    final cases = <(String, String?, ChefFamily, IconData)>[
      ('Tandoor of India', null, ChefFamily.indianMiddleEastern, Icons.kebab_dining_rounded),
      ('Shawarma Hut', null, ChefFamily.indianMiddleEastern, Icons.kebab_dining_rounded),
      ('Noodle Bar', 'Hand pulled noodles', ChefFamily.asianNoodles, Icons.ramen_dining_rounded),
      ('Wok This Way', 'Sichuan', ChefFamily.asianNoodles, Icons.ramen_dining_rounded),
      ('Hissho', 'Sushi and sashimi', ChefFamily.sushi, Icons.set_meal_rounded),
      ('Taco Truck', 'Mexican street food', ChefFamily.mexicanLatin, Icons.tapas_rounded),
      ('Mama Rosa', 'Italian classics', ChefFamily.pizzaItalian, Icons.local_pizza_rounded),
      ('Slice', 'Wood fired pizza', ChefFamily.pizzaItalian, Icons.local_pizza_rounded),
      ('Smokehouse', 'Texas BBQ', ChefFamily.bbqGrill, Icons.outdoor_grill_rounded),
      ('Island Spice', 'Jamaican jerk', ChefFamily.caribbeanRice, Icons.rice_bowl_rounded),
      ('Sweet Spot', 'Cakes and pastries', ChefFamily.desserts, Icons.cake_rounded),
      ('Early Bird', 'Breakfast all day', ChefFamily.breakfast, Icons.egg_alt_rounded),
      ('Green Plate', 'Vegan bowls', ChefFamily.saladVegan, Icons.eco_rounded),
      ('Burger Barn', 'Smash burgers', ChefFamily.burgers, Icons.lunch_dining_rounded),
      ('Sub Shop', 'Sandwiches and subs', ChefFamily.sandwichesDeli, Icons.bento_rounded),
    ];
    for (final (name, cuisine, family, icon) in cases) {
      expect(chefFamily(_chef(name, cuisine)), family, reason: name);
      expect(iconForChef(_chef(name, cuisine)).material, icon, reason: name);
    }
  });

  test('matching ignores case', () {
    expect(chefFamily(_chef('X', 'KOREAN BBQ')), chefFamily(_chef('X', 'korean bbq')));
    expect(chefFamily(_chef('PIZZA PLACE')), ChefFamily.pizzaItalian);
  });

  test('chefs nobody can place get the menu icon', () {
    expect(chefFamily(_chef('Mystery Kitchen')), ChefFamily.unknown);
    expect(chefFamily(_chef('Mystery Kitchen', '')), ChefFamily.unknown);
    expect(iconForChef(_chef('Mystery Kitchen')).material, Icons.restaurant_menu_rounded);
  });

  test('today in the fixtures', () {
    expect([for (final c in _today) chefFamily(c)], [
      ChefFamily.asianNoodles,
      ChefFamily.indianMiddleEastern,
      ChefFamily.indianMiddleEastern,
      ChefFamily.caribbeanRice,
      ChefFamily.indianMiddleEastern,
    ]);
  });

  test('chef icons are material on every platform', () {
    for (final family in ChefFamily.values) {
      expect(family.icon.cupertino, family.icon.material, reason: family.name);
      expect(AppIconKind.materialOnIos, contains(family.icon), reason: family.name);
    }
  });

  // writes the review image only when asked: ICON_SHEET=1 flutter test test/place_chef_icons_test.dart
  testWidgets('contact sheet', (tester) async {
    final home = Platform.environment['HOME']!;
    final out = File('$home/knowledge-base/tigerhub/screens/icons/place-chef-grid.png');
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1000, 1480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget panel(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness);
      return Theme(
        data: AppTheme.from(scheme),
        child: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            final text = Theme.of(context).textTheme;
            Widget cell(AppIconKind kind, String label, double width) => SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: StatusRow.badgeSize,
                      height: StatusRow.badgeSize,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withValues(alpha: 0.32)),
                      child: AppIcon(kind, color: scheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            );
            return ColoredBox(
              color: scheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Places', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(children: [for (final p in _places) cell(iconForPlace(p.id, p.name), p.name, 224)]),
                    const SizedBox(height: 16),
                    Text('Chefs', style: text.titleMedium),
                    const SizedBox(height: 8),
                    for (final family in ChefFamily.values) cell(family.icon, family.label, 448),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1000, 1480)),
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 1000,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Material(child: panel(Brightness.light))),
                    Expanded(child: Material(child: panel(Brightness.dark))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!;
    });
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  }, skip: Platform.environment['ICON_SHEET'] == null);
}
