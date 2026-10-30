/// Hiding a whole dining group, and what counts as hidden.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/dining_hidden.dart';
import 'package:tigerhub/data/dining_layout.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> file;
  late List<int> allIds;

  setUpAll(() {
    file = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
    allIds = [for (final p in file['places'] as List<dynamic>) (p as Map<String, dynamic>)['id'] as int];
  });

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await ResponseCache.instance.prune(olderThan: const Duration(days: -1));
    StaticConfig.overrideForTesting({'dining_groups': file});
    Preferences.instance.resetForTests();
  });

  Set<String> effective({
    Set<String> hidden = const {},
    Set<String> groups = const {},
    DiningLayout layout = DiningLayout.empty,
  }) {
    final config = StaticConfig.instance;
    return effectiveHiddenIds(
      hidden: hidden,
      hiddenGroups: groups,
      layout: layout,
      defaults: config.diningGroups,
      defaultGroupOf: config.diningGroupFor,
      hideIds: config.diningGroupHideIds,
      placeIds: allIds,
    );
  }

  test('the Dorm side switch hides the four named places, not all six', () {
    expect(effective(groups: {'dorm_side'}), {'21', '31', '24', '35'});
    // Corner Store and Sol's sit in the group but stay
    expect(effective(groups: {'dorm_side'}), isNot(contains('27')));
    expect(effective(groups: {'dorm_side'}), isNot(contains('28')));
  });

  test('nothing is hidden by default', () {
    expect(effective(), isEmpty);
  });

  test('a hand hide and a group hide add up', () {
    expect(effective(hidden: {'30'}, groups: {'dorm_side'}), {'30', '21', '31', '24', '35'});
  });

  test('a place moved out of the group is not hidden with it', () {
    final layout = DiningLayout.empty.move(21, 'shed', defaultGroup: 'dorm_side');
    expect(effective(groups: {'dorm_side'}, layout: layout), {'31', '24', '35'});
  });

  test('a place moved in is not hidden unless the group lists it', () {
    final layout = DiningLayout.empty.move(30, 'dorm_side', defaultGroup: 'shed');
    expect(effective(groups: {'dorm_side'}, layout: layout), isNot(contains('30')));
  });

  test('a group without a hide list hides everything that resolves into it', () {
    final shed = [
      for (final p in file['places'] as List<dynamic>)
        if ((p as Map<String, dynamic>)['group'] == 'shed') p['id'] as int,
    ];
    expect(shed, isNotEmpty);
    expect(effective(groups: {'shed'}), {for (final id in shed) '$id'});
  });

  test('Other cannot be hidden', () async {
    await Preferences.instance.setGroupHidden('other', true);
    expect(Preferences.instance.hiddenDiningGroups, isEmpty);
    expect(effective(groups: {'other'}), isEmpty);
  });

  test('a group hide survives a reload', () async {
    await Preferences.instance.setGroupHidden('dorm_side', true);
    Preferences.instance.resetForTests();
    await Preferences.instance.load();
    expect(Preferences.instance.hiddenDiningGroups, {'dorm_side'});
  });

  test('pins stay stored while their group is hidden', () async {
    await Preferences.instance.togglePinned(21);
    await Preferences.instance.setGroupHidden('dorm_side', true);
    expect(Preferences.instance.pinnedDining, {'21'});
    expect(Preferences.instance.effectiveHidden([21]), {'21'});
  });

  test('deleting a custom group drops its hide', () async {
    final prefs = Preferences.instance;
    await prefs.setDiningLayout(prefs.diningLayout.addCustom('Mine'));
    await prefs.setGroupHidden('custom-1', true);
    await prefs.setGroupHidden('dorm_side', true);
    await prefs.setDiningLayout(prefs.diningLayout.removeCustom('custom-1'));
    expect(prefs.hiddenDiningGroups, {'dorm_side'});
  });

  test('undo restores the group set along with the places', () async {
    final prefs = Preferences.instance;
    await prefs.setGroupHidden('dorm_side', true);
    await prefs.toggleHidden(30);
    await prefs.unhideAllDining();
    expect(prefs.hiddenDining, isEmpty);
    expect(prefs.hiddenDiningGroups, isEmpty);
    await prefs.restoreDining(pinned: {}, hidden: {'30'}, hiddenGroups: {'dorm_side'});
    expect(prefs.hiddenDining, {'30'});
    expect(prefs.hiddenDiningGroups, {'dorm_side'});
  });

  test('the places a hidden group covers come from the table with names', () async {
    await Preferences.instance.setGroupHidden('dorm_side', true);
    final places = Preferences.instance.groupHiddenPlaces;
    expect([for (final p in places) p.id]..sort(), [21, 24, 31, 35]);
    expect([for (final p in places) p.name], contains("Gracie's"));
  });

  test('clearing home leaves setup answered', () async {
    final prefs = Preferences.instance;
    await prefs.setHome(area: 'global-village');
    await prefs.markSetupSeen();
    await prefs.clearHome();
    expect(prefs.homeArea, isNull);
    expect(prefs.setupSeen, isTrue);
    prefs.resetForTests();
    await prefs.load();
    expect(prefs.setupSeen, isTrue);
  });
}
