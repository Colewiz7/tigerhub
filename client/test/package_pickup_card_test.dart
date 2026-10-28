/// The Package pickup card: the scheduled counter hours at the post office
/// for where you live.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/package_pickup_card.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/compact_card.dart';

Map<String, dynamic> _config(String name) => jsonDecode(File('assets/config/$name.json').readAsStringSync()) as Map<String, dynamic>;

final _areas = [
  for (final a in _config('housing_areas')['areas'] as List<dynamic>) HousingArea.fromJson(a as Map<String, dynamic>),
  for (final d in _config('housing_areas')['direct_delivery'] as List<dynamic>) HousingArea.fromJson({...d as Map<String, dynamic>, 'direct_delivery': true}),
];
final _offices = [for (final o in _config('post_offices')['offices'] as List<dynamic>) PostOffice.fromJson(o as Map<String, dynamic>)];

// tue oct 13, fri oct 16, sat oct 17 2026
({String? value, String? caption, bool quiet}) _at(String? area, int day, int hour, [int minute = 0]) =>
    packagePickupCompact(areas: _areas, offices: _offices, area: area, now: CampusTime.wall(2026, 10, day, hour, minute));

void main() {
  group('the answer', () {
    test('residence halls use DSP, open on a tuesday morning until 4:30 PM', () {
      expect(_at('residence-halls', 13, 10), (value: 'Until 4:30 PM', caption: 'Scheduled', quiet: false));
    });

    test('before it opens it says when', () {
      expect(_at('global-village', 13, 8), (value: 'Opens 9 AM', caption: 'Scheduled', quiet: true));
    });

    test('after closing on a weekday the next opening is tomorrow', () {
      expect(_at('global-village', 13, 17), (value: 'Closed today', caption: 'Opens 9 AM tomorrow', quiet: true));
    });

    test('friday evening opens saturday at noon', () {
      expect(_at('global-village', 16, 17).caption, 'Opens 12 PM tomorrow');
    });

    test('saturday evening is closed with no opening tomorrow', () {
      expect(_at('global-village', 17, 17), (value: 'Closed today', caption: 'Scheduled', quiet: true));
    });

    test('greek houses use the global village office', () {
      expect(_at('greek-houses', 13, 10).value, 'Until 4:30 PM');
    });

    test('direct delivery says front desk, no home says set home', () {
      expect(_at('rit-inn', 13, 10).value, 'Front desk');
      expect(_at('175-jefferson', 13, 10).value, 'Front desk');
      expect(_at(null, 13, 10).value, 'Set home');
    });

    test('before the offices load there is no value', () {
      expect(packagePickupCompact(areas: _areas, offices: const [], area: 'global-village', now: CampusTime.wall(2026, 10, 13, 10)).value, isNull);
    });

    test('every value fits a compact card', () {
      for (final area in ['residence-halls', 'global-village', 'rit-inn', null]) {
        for (var day = 12; day <= 18; day++) {
          for (var hour = 0; hour < 24; hour++) {
            expect((_at(area, day, hour).value ?? '').length, lessThanOrEqualTo(13));
          }
        }
      }
    });
  });

  test('package pickup is a compact card type in the library', () {
    expect(ModuleType.byId('package_pickup'), ModuleType.packagePickup);
    expect(supportedSizes[ModuleType.packagePickup], [CardSize.compact]);
    expect(moduleLabels[ModuleType.packagePickup], 'Package pickup');
    expect(compactBodyTypes, contains(ModuleType.packagePickup));
  });

  testWidgets('on a phone the card reads home and opens Campus', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(CampusTime.wall(2026, 10, 13, 10));
    addTearDown(() {
      RitClock.reset();
      Preferences.instance.resetForTests();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await Preferences.instance.setHome(area: 'global-village');
    final taps = <int>[];
    Result<Collection<T>> ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 174, child: PackagePickupCard(areas: ok(_areas), offices: ok(_offices), onShowAll: () => taps.add(4))))),
    ));
    await tester.pump();
    expect(find.byType(CompactCard), findsOneWidget);
    expect(find.text('Until 4:30 PM'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    await tester.tap(find.text('Until 4:30 PM'));
    expect(taps, [4]);
  });
}
