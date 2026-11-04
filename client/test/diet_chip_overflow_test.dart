/// Dietary chips wrap inside the dish row and never overflow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/menu_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
  });

  final menu = MenuDay(
    locationId: 1,
    serviceDate: DateTime(2026, 10, 14),
    dishes: [
      Dish(
        name: 'Sesame noodle bowl with seasonal vegetables and chili crisp',
        category: 'Asian',
        dietary: const ['Vegan', 'Made without gluten-containing ingredients'],
        allergens: const [
          'Sesame',
          'Soy',
          'Tree nuts and peanuts processed together',
        ],
      ),
    ],
  );

  for (final width in [390.0, 440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final flagged in [false, true]) {
        testWidgets(
          'diet chips fit at $width wide, ${scale}x text, flagged $flagged',
          (tester) async {
            if (flagged) {
              await Preferences.instance.toggleAvoid(
                'Tree nuts and peanuts processed together',
              );
            }
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 1600);
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.from(
                  ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: MenuSection(menu: menu, prefs: Preferences.instance),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            expect(find.textContaining('gluten-containing'), findsOneWidget);
          },
        );
      }
    }
  }
}
