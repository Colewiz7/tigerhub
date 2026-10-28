/// Dishes are tinted by diet or protein, and never by colour alone.
///
/// The class comes only from the tags RIT publishes. The feed carries
/// Vegetarian, Vegan, Pork and Beef; chicken and fish are recognised if a tag
/// ever says so, and are never guessed from a dish name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/models/diet_class.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/diet_palette.dart';
import 'package:tigerhub/widgets/menu_section.dart';

Dish _dish(
  String name, {
  List<String> diet = const [],
  List<String> allergens = const [],
  String? category = 'Grill',
}) => Dish(name: name, category: category, dietary: diet, allergens: allergens);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _orange = Color(0xFFF76902);

ColorScheme _scheme(Brightness b, [Color seed = _orange]) =>
    ColorScheme.fromSeed(seedColor: seed, brightness: b);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
  });

  group('classification', () {
    final cases = <String, (DietClass, Dish)>{
      'vegan': (DietClass.vegan, _dish('a', diet: ['Vegan', 'Vegetarian'])),
      'vegetarian': (DietClass.vegetarian, _dish('a', diet: ['Vegetarian'])),
      'beef': (DietClass.beef, _dish('a', diet: ['Beef'])),
      'pork': (DietClass.pork, _dish('a', diet: ['Pork'])),
      'chicken': (DietClass.chicken, _dish('a', diet: ['Chicken'])),
      'fish from an allergen tag': (DietClass.fish, _dish('a', allergens: ['Fish'])),
      'meat beats vegetarian': (DietClass.pork, _dish('a', diet: ['Vegetarian', 'Pork'])),
      'case does not matter': (DietClass.beef, _dish('a', diet: ['bEEf'])),
      'no tags': (DietClass.other, _dish('Chicken salad')),
      'a name is never read': (DietClass.other, _dish('Grilled salmon')),
      'a traces note is not the protein': (
        DietClass.other,
        _dish('a', allergens: ['May Contain Traces of Fish']),
      ),
      'unrelated allergens': (DietClass.other, _dish('a', allergens: ['Milk', 'Egg'])),
      'non-vegetarian is not vegetarian': (DietClass.other, _dish('a', diet: ['Non-Vegetarian'])),
      'non vegetarian is not vegetarian': (DietClass.other, _dish('a', diet: ['non vegetarian'])),
      'non-vegan is not vegan': (DietClass.other, _dish('a', diet: ['Non-Vegan'])),
      'a longer tag is not vegetarian': (DietClass.other, _dish('a', diet: ['Vegetarian Option'])),
      'padded vegetarian': (DietClass.vegetarian, _dish('a', diet: ['  Vegetarian '])),
      'padded vegan': (DietClass.vegan, _dish('a', diet: ['\tVegan\n'])),
      'padded pork': (DietClass.pork, _dish('a', diet: [' Pork '])),
      'padded fish allergen': (DietClass.fish, _dish('a', allergens: [' Fish '])),
    };
    for (final entry in cases.entries) {
      test(entry.key, () => expect(dietClassOf(entry.value.$2), entry.value.$1));
    }

    test('the label is the tag as published, trimmed', () {
      expect(classifyDish(_dish('a', diet: ['bEEf'])).tag, 'bEEf');
      expect(classifyDish(_dish('a', diet: [' Vegan '])).tag, 'Vegan');
      expect(classifyDish(_dish('a')).tag, isNull);
    });

    test('the diet filter agrees: non-vegetarian is not vegetarian', () {
      expect(_dish('a', diet: ['Non-Vegetarian']).isVegetarian, isFalse);
      expect(_dish('a', diet: [' Vegetarian ']).isVegetarian, isTrue);
      expect(_dish('a', diet: ['Non-Vegan']).isVegan, isFalse);
    });
  });

  group('palette', () {
    for (final brightness in Brightness.values) {
      for (final kind in DietClass.values) {
        test('${kind.name} text reads at 4.5:1 in ${brightness.name}', () {
          final palette = DietPalette.from(_scheme(brightness));
          final c = palette[kind];
          expect(_contrast(c.onContainer, c.container), greaterThanOrEqualTo(4.5));
          expect(_contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
        });
      }

      test('the six classes are six different backgrounds in ${brightness.name}', () {
        final palette = DietPalette.from(_scheme(brightness));
        final tints = {
          for (final kind in DietClass.values) palette[kind].container.toARGB32(),
        };
        expect(tints.length, DietClass.values.length);
      });
    }

    test('is part of the app theme', () {
      final theme = AppTheme.from(_scheme(Brightness.dark));
      expect(theme.extension<DietPalette>(), isNotNull);
    });
  });

  Future<void> pumpMenu(
    WidgetTester tester,
    List<Dish> dishes, {
    Brightness brightness = Brightness.light,
    Widget Function(Widget menu)? wrap,
    double width = 390,
    double scale = 1,
    Color seed = _orange,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.reset);
    final menu = MenuSection(
      menu: MenuDay(locationId: 1, serviceDate: DateTime(2026, 10, 14), dishes: dishes),
      prefs: Preferences.instance,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(_scheme(brightness, seed)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: wrap == null ? menu : wrap(menu)),
        ),
      ),
    );
  }

  group('dish rows', () {
    final dishes = [
      _dish('Tofu bowl', diet: ['Vegan', 'Vegetarian']),
      _dish('Cheese slice', diet: ['Vegetarian']),
      _dish('Brisket', diet: ['Beef']),
      _dish('Ham melt', diet: ['Pork']),
      _dish('Plain rice'),
    ];

    for (final brightness in Brightness.values) {
      testWidgets('tint each row by class in ${brightness.name}', (tester) async {
        await pumpMenu(tester, dishes, brightness: brightness);
        final palette = DietPalette.from(_scheme(brightness));
        final scheme = _scheme(brightness);

        Color? tintOf(String name) {
          final row = find.ancestor(
            of: find.text(name),
            matching: find.byKey(ValueKey('dish-$name')),
          );
          final box = tester.widget<Container>(row);
          return (box.decoration! as BoxDecoration).color;
        }

        expect(tintOf('Tofu bowl'), palette[DietClass.vegan].container);
        expect(tintOf('Cheese slice'), palette[DietClass.vegetarian].container);
        expect(tintOf('Brisket'), palette[DietClass.beef].container);
        expect(tintOf('Ham melt'), palette[DietClass.pork].container);
        expect(tintOf('Plain rice'), scheme.surfaceContainerHigh);
      });
    }

    testWidgets('every tinted row also carries a text label and an icon', (tester) async {
      await pumpMenu(tester, dishes);

      for (final (name, label) in [
        ('Tofu bowl', 'Vegan'),
        ('Cheese slice', 'Vegetarian'),
        ('Brisket', 'Beef'),
        ('Ham melt', 'Pork'),
      ]) {
        final chip = find.descendant(
          of: find.byKey(ValueKey('dish-$name')),
          matching: find.byKey(ValueKey('diet-label-$label')),
        );
        expect(chip, findsOneWidget, reason: name);
        expect(
          find.descendant(of: chip, matching: find.byType(Icon)),
          findsOneWidget,
          reason: '$name icon',
        );
        expect(find.descendant(of: chip, matching: find.text(label)), findsOneWidget);
      }
    });

    testWidgets('a published tag is shown once, other tags stay', (tester) async {
      await pumpMenu(tester, dishes);

      final row = find.byKey(const ValueKey('dish-Tofu bowl'));
      expect(find.descendant(of: row, matching: find.text('Vegan')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Vegetarian')), findsOneWidget);
    });

    testWidgets('an untagged dish carries no diet label', (tester) async {
      await pumpMenu(tester, dishes);

      final row = find.byKey(const ValueKey('dish-Plain rice'));
      expect(
        find.descendant(of: row, matching: find.byWidgetPredicate(
          (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('diet-label-'),
        )),
        findsNothing,
      );
    });

    // every Text in the row, against the fill it is actually painted on
    void expectReadable(WidgetTester tester, String dish, String state) {
      final row = find.byKey(ValueKey('dish-$dish'));
      expect(row, findsOneWidget, reason: dish);
      final rowFill = (tester.widget<Container>(row).decoration! as BoxDecoration).color!;

      void check(Element element, Color fill) {
        final text = element.widget as Text;
        final color = text.style?.color;
        expect(color, isNotNull, reason: '$dish "${text.data}" has no explicit color ($state)');
        expect(
          _contrast(color!, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$dish "${text.data}" $state',
        );
      }

      final painted = <Element>{};
      for (final material in find.descendant(of: row, matching: find.byType(Material)).evaluate()) {
        final fill = (material.widget as Material).color!;
        for (final text in find.descendant(
          of: find.byWidget(material.widget),
          matching: find.byType(Text),
        ).evaluate()) {
          painted.add(text);
          check(text, fill);
        }
      }
      for (final text in find.descendant(of: row, matching: find.byType(Text)).evaluate()) {
        if (!painted.contains(text)) check(text, rowFill);
      }
      expect(
        find.ancestor(of: row, matching: find.byType(Opacity)),
        findsNothing,
        reason: '$dish is faded, which no contrast check can see ($state)',
      );
    }

    final everyClass = [
      _dish('Tofu bowl', diet: ['Vegan', 'Vegetarian']),
      _dish('Cheese slice', diet: ['Vegetarian']),
      _dish('Brisket', diet: ['Beef']),
      _dish('Ham melt', diet: ['Pork']),
      _dish('Roast bird', diet: ['Chicken'], category: 'Grill'),
      _dish('Fish fry', allergens: ['Fish', 'Milk']),
      _dish('Plain rice', allergens: ['Gluten']),
    ];

    const seeds = {
      'orange': _orange,
      'blue': Color(0xFF1565C0),
      'green': Color(0xFF2E7D32),
      'purple': Color(0xFF6750A4),
    };

    for (final brightness in Brightness.values) {
      for (final seed in seeds.entries) {
        testWidgets('rendered text reads at 4.5:1, ${brightness.name}, ${seed.key} seed', (
          tester,
        ) async {
          await pumpMenu(tester, everyClass, brightness: brightness, seed: seed.value);
          for (final dish in everyClass) {
            expectReadable(tester, dish.name, 'unfiltered');
          }
        });

        testWidgets('demoted rows still read at 4.5:1, ${brightness.name}, ${seed.key} seed', (
          tester,
        ) async {
          await Preferences.instance.toggleDiet('Vegan');
          await pumpMenu(tester, everyClass, brightness: brightness, seed: seed.value);
          for (final dish in everyClass) {
            expectReadable(tester, dish.name, 'demoted by a Vegan filter');
          }
        });
      }
    }

    testWidgets('a demoted row says so in words, a matching row does not', (tester) async {
      await Preferences.instance.toggleDiet('Vegan');
      await pumpMenu(tester, everyClass);

      Finder label(String dish) => find.descendant(
        of: find.byKey(ValueKey('dish-$dish')),
        matching: find.text('Doesn’t match'),
      );
      expect(label('Tofu bowl'), findsNothing);
      expect(label('Brisket'), findsOneWidget);
      expect(label('Plain rice'), findsOneWidget);
    });

    testWidgets('no filter, no demotion label', (tester) async {
      await pumpMenu(tester, everyClass);
      expect(find.text('Doesn’t match'), findsNothing);
    });
  });

  group('legend', () {
    testWidgets('names all seven classes', (tester) async {
      await pumpMenu(tester, const [], wrap: (_) => const DietLegend());
      final legend = find.byKey(const ValueKey('diet-legend'));

      for (final label in ['Vegan', 'Vegetarian', 'Beef', 'Pork', 'Chicken', 'Fish', 'Other']) {
        expect(find.descendant(of: legend, matching: find.text(label)), findsOneWidget, reason: label);
      }
    });

    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fits at $width wide, ${scale}x text', (tester) async {
          await pumpMenu(tester, const [], wrap: (_) => const DietLegend(), width: width, scale: scale);

          expect(tester.takeException(), isNull);
          final box = tester.getRect(find.byKey(const ValueKey('diet-legend')));
          expect(box.right, lessThanOrEqualTo(width));
        });
      }
    }
  });
}
