/// Visiting chefs at places a hidden dining group hides.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/chef_listing.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const byId = MenuItem(id: 1, name: 'Tandoor', locationName: 'whatever the feed says', locationId: 21);
  const byName = MenuItem(id: 2, name: 'KO-BQ', locationName: 'Gracies');
  const elsewhere = MenuItem(id: 3, name: 'Pho Real', locationName: 'RITZ', locationId: 26);
  const unknown = MenuItem(id: 4, name: 'Mystery', locationName: 'A truck by the quad');
  const noPlace = MenuItem(id: 5, name: 'Nowhere', locationName: '');
  const chefs = [byId, byName, elsewhere, unknown, noPlace];

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await ResponseCache.instance.prune(olderThan: const Duration(days: -1));
    final file = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
    StaticConfig.overrideForTesting({'dining_groups': file});
    Preferences.instance.resetForTests();
  });

  tearDown(Preferences.instance.resetForTests);

  test('the id decides first, then the name through the aliases', () async {
    await Preferences.instance.setGroupHidden('dorm_side', true);
    final kept = withoutHiddenChefs(chefs, Preferences.instance.groupHiddenPlaces);
    expect([for (final c in kept) c.name], ['Pho Real', 'Mystery', 'Nowhere']);
  });

  test('a location nobody can place stays visible', () async {
    await Preferences.instance.setGroupHidden('dorm_side', true);
    expect(atHiddenPlace('A truck by the quad', Preferences.instance.groupHiddenPlaces), isFalse);
    expect(atHiddenPlace('', Preferences.instance.groupHiddenPlaces), isFalse);
  });

  test('nothing changes with no hidden group', () {
    expect(withoutHiddenChefs(chefs, Preferences.instance.groupHiddenPlaces), chefs);
  });

  test('a chef at a place hidden by hand stays', () async {
    await Preferences.instance.toggleHidden(21);
    expect(withoutHiddenChefs(chefs, Preferences.instance.groupHiddenPlaces), chefs);
  });

  Future<void> pumpCard(WidgetTester tester, List<MenuItem> data) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: SingleChildScrollView(
          child: VisitingChefsCard(result: Result(value: Collection(data: data, stale: false), state: DataState.ok)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the Today card follows the switch live', (tester) async {
    await pumpCard(tester, [byId, elsewhere]);
    expect(find.text('Tandoor'), findsOneWidget);

    await Preferences.instance.setGroupHidden('dorm_side', true);
    await tester.pumpAndSettle();
    expect(find.text('Tandoor'), findsNothing);
    expect(find.text('Pho Real'), findsOneWidget);
  });

  testWidgets('every chef hidden reads as no visiting chefs today', (tester) async {
    await Preferences.instance.setGroupHidden('dorm_side', true);
    await pumpCard(tester, [byId, byName]);
    expect(find.text('No visiting chefs today'), findsOneWidget);
    expect(find.text('No more chefs today'), findsNothing);
  });
}
