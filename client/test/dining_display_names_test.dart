/// Crossroads and Market are drawn short; every id, alias and search keeps
/// the full name. Chef specials lead the detail menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/chef_listing.dart';
import 'package:tigerhub/data/chef_location_color.dart';
import 'package:tigerhub/data/dining_display_names.dart';
import 'package:tigerhub/data/sources/rit_chefs.dart' show locationKey;
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/dining_detail_sheet.dart';
import 'package:tigerhub/widgets/menu_section.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'support/dining_harness.dart';

const _crossroads = 'The Cafe & Market at Crossroads';
const _market = 'The Market at Global Village';

final _places = [
  place(23, _crossroads),
  place(29, _market),
  place(481, 'Bytes Micro Market', open: false),
  place(461, 'Petals'),
];

const _chef = MenuItem(
  id: 1,
  name: 'KO-BQ',
  locationName: _crossroads,
  locationId: 23,
  category: 'Visiting Chef',
);

// the type chips say Market too, so look inside the rows
Finder rowTitle(String title) => find.descendant(of: find.byType(StatusRow), matching: find.text(title));

Dish _dish(String name, String? category) => Dish(name: name, category: category);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpDining();

  group('helper', () {
    test('shortens by id and by every name RIT has used', () {
      expect(diningDisplayName(23, _crossroads), 'Crossroads');
      expect(diningDisplayName(null, 'Cafe & Market at Crossroads'), 'Crossroads');
      expect(diningDisplayName(null, 'Cafe and Market at Crossroads'), 'Crossroads');
      expect(diningDisplayName(null, 'Market at Crossroads'), 'Crossroads');
      expect(diningDisplayName(29, _market), 'Market');
      expect(diningDisplayName(null, 'Market at Global Village'), 'Market');
    });

    test('leaves other places alone', () {
      for (final name in ['Corner Store', 'Bytes Micro Market', 'Patio at Global Village', 'Midnight Oil', 'Global Village']) {
        expect(diningDisplayName(null, name), name);
      }
      expect(diningDisplayName(481, 'Bytes Micro Market'), 'Bytes Micro Market');
    });

    test('ids, aliases, colours and icons keep working on the full name', () {
      expect(locationKey(_crossroads), locationKey('Crossroads'));
      expect(chefLocationColors[23]!.name, _crossroads);
      expect(chefLocationId(_chef), 23);
      expect(iconForPlace(23, _crossroads), AppIconKind.dining);
      expect(iconForVenue(_crossroads), AppIconKind.diningHall);
      expect(diningFullName(23, _crossroads), _crossroads);
      expect(diningFullName(461, 'Petals'), isNull);
    });

    test('the Next line and chef place use the short name', () {
      final next = UpcomingChef(date: DateTime.utc(2026, 10, 16), name: 'Chef Lin', locationName: _crossroads);
      expect(nextChefLine(next, DateTime.utc(2026, 10, 14)), contains('Crossroads'));
      expect(nextChefLine(next, DateTime.utc(2026, 10, 14)), isNot(contains('Cafe')));
      expect(chefPlaceName(_chef), 'Crossroads');
    });
  });

  group('dining tab', () {
    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('rows read short at $width, ${scale}x', (tester) async {
          await pumpDiningScreen(tester, places: _places, size: Size(width, 1600), scale: scale);
          expect(find.text('Crossroads'), findsOneWidget);
          expect(rowTitle('Market'), findsOneWidget);
          expect(find.text(_crossroads), findsNothing);
          expect(find.text(_market), findsNothing);
          expect(find.text('Petals'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the long name and Global Village still find the places', (tester) async {
      await pumpDiningScreen(tester, places: _places);
      await tester.enterText(find.byType(TextField).first, 'cafe & market at');
      await tester.pumpAndSettle();
      expect(find.text('Crossroads'), findsOneWidget);
      expect(rowTitle('Market'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'market at global village');
      await tester.pumpAndSettle();
      expect(rowTitle('Market'), findsOneWidget);
      expect(find.text('Crossroads'), findsNothing);
    });

    testWidgets('a pinned place reads short with its pin', (tester) async {
      await Preferences.instance.togglePinned(29);
      await pumpDiningScreen(tester, places: _places);
      expect(rowTitle('Market'), findsWidgets);
      expect(find.text(_market), findsNothing);
    });
  });

  testWidgets('Today eat now rows read short', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiningCard(result: Result(value: Collection(data: _places, stale: false), state: DataState.ok)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crossroads'), findsOneWidget);
    expect(find.text(_crossroads), findsNothing);
  });

  group('chef rows', () {
    testWidgets('the Today chefs card writes the short place', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisitingChefsCard(
                result: Result(value: ChefCollection(data: const [_chef], stale: false), state: DataState.ok),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Crossroads'), findsWidgets);
      expect(find.textContaining('Cafe &'), findsNothing);
    });
  });

  group('detail', () {
    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('short title, full name under it at $width, ${scale}x', (tester) async {
          SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
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
              home: DiningDetailPage(location: _places.first, api: ApiClient(backend: EmptyBackend())),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.descendant(of: find.byType(AppBar), matching: find.text('Crossroads')), findsOneWidget);
          expect(find.byKey(const ValueKey('detail-full-name')), findsOneWidget);
          expect(find.text(_crossroads), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a place with no short name has no subtitle', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
          home: DiningDetailPage(location: _places.last, api: ApiClient(backend: EmptyBackend())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('detail-full-name')), findsNothing);
    });
  });

  group('chef specials station', () {
    Future<void> pump(WidgetTester tester, List<Dish> dishes) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MenuSection(
                menu: MenuDay(locationId: 23, serviceDate: DateTime(2026, 10, 14), dishes: dishes),
                prefs: Preferences.instance,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('leads the list and opens, the old first stays open', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 2400);
      addTearDown(tester.view.reset);
      await pump(tester, [
        _dish('Burger', 'Grill'),
        _dish('Pad thai', 'Asian'),
        _dish('Braised short rib', "Chef's Specials"),
        _dish('Mystery', null),
      ]);
      final tops = [
        for (final s in ["Chef's Specials", 'Grill', 'Asian', 'Other'])
          tester.getTopLeft(find.byKey(ValueKey('station-$s'))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.text('Braised short rib'), findsOneWidget);
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('Pad thai'), findsNothing);
    });

    testWidgets('matches special in any case', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 2400);
      addTearDown(tester.view.reset);
      await pump(tester, [_dish('Burger', 'Grill'), _dish('Soup', 'DAILY SPECIAL')]);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('station-DAILY SPECIAL'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('station-Grill'))).dy),
      );
    });

    testWidgets('a menu with no specials is unchanged', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 2400);
      addTearDown(tester.view.reset);
      await pump(tester, [_dish('Burger', 'Grill'), _dish('Pad thai', 'Asian')]);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('station-Grill'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('station-Asian'))).dy),
      );
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('Pad thai'), findsNothing);
    });
  });
}
