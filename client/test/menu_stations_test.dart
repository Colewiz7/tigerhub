/// The menu groups dishes under collapsible station sections.
///
/// The station is the dish's published `category`. A dish with none goes under
/// Other. Every section but the first starts folded, and a dietary filter
/// opens any section holding a match, so folding never hides a wanted dish.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/menu_section.dart';

Dish _dish(String name, {String? category, List<String> diet = const []}) =>
    Dish(name: name, category: category, dietary: diet);

MenuDay _menu(List<Dish> dishes) => MenuDay(
  locationId: 1,
  serviceDate: DateTime(2026, 10, 14),
  dishes: dishes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
  });

  Future<void> pump(
    WidgetTester tester,
    MenuDay menu, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MenuSection(menu: menu, prefs: Preferences.instance),
          ),
        ),
      ),
    );
  }

  final menu = _menu([
    _dish('Burger', category: 'Grill'),
    _dish('Hot dog', category: 'Grill'),
    _dish('Pad thai', category: 'Asian'),
    _dish('Margherita', category: 'Pizza'),
    _dish('Mystery dish'),
  ]);

  Finder header(String station) => find.byKey(ValueKey('station-$station'));

  testWidgets('one section per station, with an item count, Other last', (tester) async {
    await pump(tester, menu);

    expect(header('Grill'), findsOneWidget);
    expect(header('Asian'), findsOneWidget);
    expect(header('Pizza'), findsOneWidget);
    expect(header('Other'), findsOneWidget);
    expect(find.descendant(of: header('Grill'), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: header('Asian'), matching: find.text('1')), findsOneWidget);
    expect(
      tester.getTopLeft(header('Other')).dy,
      greaterThan(tester.getTopLeft(header('Pizza')).dy),
    );
  });

  testWidgets('only the first section starts open', (tester) async {
    await pump(tester, menu);

    expect(find.text('Burger'), findsOneWidget);
    expect(find.text('Hot dog'), findsOneWidget);
    expect(find.text('Pad thai'), findsNothing);
    expect(find.text('Margherita'), findsNothing);
    expect(find.text('Mystery dish'), findsNothing);
  });

  testWidgets('tapping a header opens and folds its section', (tester) async {
    await pump(tester, menu);

    await tester.tap(header('Asian'));
    await tester.pumpAndSettle();
    expect(find.text('Pad thai'), findsOneWidget);

    await tester.tap(header('Asian'));
    await tester.pumpAndSettle();
    expect(find.text('Pad thai'), findsNothing);

    await tester.tap(header('Grill'));
    await tester.pumpAndSettle();
    expect(find.text('Burger'), findsNothing);
  });

  testWidgets('headers are at least 48 tall and announce their state', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, menu, scale: 2);

    expect(tester.getSize(header('Asian')).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(header('Asian')),
      matchesSemantics(
        label: 'Asian, 1 item',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );
    handle.dispose();
  });

  testWidgets('a dietary filter opens the sections that hold a match', (tester) async {
    await Preferences.instance.toggleDiet('Vegan');
    await pump(
      tester,
      _menu([
        _dish('Burger', category: 'Grill'),
        _dish('Tofu bowl', category: 'Asian', diet: ['Vegan']),
      ]),
    );

    expect(find.text('Tofu bowl'), findsOneWidget);
  });

  for (final width in [390.0, 440.0]) {
    testWidgets('long station names wrap at 2x text, $width wide', (tester) async {
      await pump(
        tester,
        _menu([
          _dish('Burger', category: 'Grill and flat top and all day breakfast station'),
          _dish('Pad thai', category: 'Asian'),
        ]),
        width: width,
        scale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Burger'), findsOneWidget);
    });
  }
}
