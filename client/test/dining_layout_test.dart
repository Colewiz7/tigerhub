/// Layout deltas: resolving, diffs from defaults, and the saved copy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/dining_layout.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';

const _defaults = <GroupDef>[
  (id: 'a', name: 'Alpha'),
  (id: 'b', name: 'Beta'),
  (id: 'c', name: 'Gamma'),
  (id: 'other', name: 'Other'),
];

String _home(int id) => switch (id) {
  1 || 2 => 'a',
  3 => 'b',
  4 => 'c',
  _ => 'other',
};

List<ResolvedGroup> _resolve(DiningLayout layout, [List<int> places = const [1, 2, 3, 4, 5]]) =>
    layout.resolve(defaults: _defaults, defaultGroupOf: _home, placeIds: places);

List<String> _ids(List<ResolvedGroup> groups) => [for (final g in groups) g.id];

void main() {
  test('an empty layout is the defaults and saves nothing', () {
    final groups = _resolve(DiningLayout.empty);
    expect(_ids(groups), ['a', 'b', 'c', 'other']);
    expect(groups.first.placeIds, [1, 2]);
    expect(groups.last.placeIds, [5]);
    expect(DiningLayout.empty.encode(), isNull);
  });

  test('edits that match the defaults leave no diff', () {
    var layout = DiningLayout.empty;
    layout = layout.rename('a', 'Renamed', defaultName: 'Alpha').rename('a', 'Alpha', defaultName: 'Alpha');
    layout = layout.move(1, 'b', defaultGroup: 'a').move(1, 'a', defaultGroup: 'a');
    layout = layout.reorder(['a', 'b', 'c', 'other'], ['a', 'b', 'c', 'other']);
    expect(layout.isEmpty, isTrue);
  });

  test('reorder, rename and move resolve and round trip', () {
    var layout = DiningLayout.empty;
    layout = layout.reorder(['c', 'a', 'b', 'other'], ['a', 'b', 'c', 'other']);
    layout = layout.rename('b', 'Bee', defaultName: 'Beta');
    layout = layout.move(2, 'c', defaultGroup: 'a');
    layout = layout.addCustom('Mine').move(5, 'custom-1', defaultGroup: 'other');
    final back = DiningLayout.parse(layout.encode());
    final groups = _resolve(back);
    expect(_ids(groups), ['c', 'a', 'b', 'custom-1', 'other']);
    expect(groups.firstWhere((g) => g.id == 'b').name, 'Bee');
    expect(groups.firstWhere((g) => g.id == 'c').placeIds, [2, 4]);
    expect(groups.firstWhere((g) => g.id == 'custom-1').isDefault, isFalse);
    expect(groups.firstWhere((g) => g.id == 'custom-1').placeIds, [5]);
  });

  test('Other stays last whatever the saved order says', () {
    final layout = DiningLayout.parse('{"v":1,"order":["other","b"]}');
    expect(_ids(_resolve(layout)), ['b', 'a', 'c', 'other']);
  });

  test('deleting a custom group sends its places home', () {
    final layout = DiningLayout.empty.addCustom('Mine').move(1, 'custom-1', defaultGroup: 'a');
    expect(_resolve(layout).firstWhere((g) => g.id == 'custom-1').placeIds, [1]);
    final removed = layout.removeCustom('custom-1');
    expect(removed.isEmpty, isTrue);
    expect(_resolve(removed).first.placeIds, [1, 2]);
  });

  test('a move into a group that no longer exists falls back to the table', () {
    final layout = DiningLayout.parse('{"v":1,"moved":{"1":"custom-9"}}');
    expect(_resolve(layout).first.placeIds, [1, 2]);
  });

  test('saved place order sorts first, the rest follow', () {
    final layout = DiningLayout.empty.orderPlaces('a', [2, 99]);
    expect(_resolve(layout).first.placeIds, [2, 1]);
  });

  test('corrupt or newer data falls back to the defaults', () {
    for (final raw in ['{', '[]', 'null', '"x"', '{"v":2,"order":["b"]}', '{"v":1,"order":"b"}', '{"v":1,"moved":{"x":"a"}}', '{"v":1,"custom":[1]}', '{"order":["b"]}']) {
      expect(DiningLayout.parse(raw).isEmpty, isTrue, reason: raw);
    }
  });

  group('storage', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      Preferences.instance.resetForTests();
    });
    tearDown(Preferences.instance.resetForTests);

    test('layout and hidden places survive a reload', () async {
      final prefs = Preferences.instance;
      await prefs.setDiningLayout(DiningLayout.empty.addCustom('Mine'));
      await prefs.toggleHidden(7);
      prefs.resetForTests();
      expect(prefs.diningLayout.isEmpty, isTrue);
      await prefs.load();
      expect(prefs.diningLayout.custom, {'custom-1': 'Mine'});
      expect(prefs.hiddenDining, {'7'});
      expect(prefs.isHidden(7), isTrue);
    });

    test('a corrupt saved layout loads as the defaults', () async {
      await ResponseCache.instance.writeOrder('dining_layout', ['{not json']);
      await Preferences.instance.load();
      expect(Preferences.instance.diningLayout.isEmpty, isTrue);
    });

    test('reset and unhide clear the saved copy', () async {
      final prefs = Preferences.instance;
      await prefs.setDiningLayout(DiningLayout.empty.addCustom('Mine'));
      await prefs.toggleHidden(7);
      await prefs.resetDiningGroups();
      await prefs.unhideAllDining();
      prefs.resetForTests();
      await prefs.load();
      expect(prefs.diningLayout.isEmpty, isTrue);
      expect(prefs.hiddenDining, isEmpty);
    });
  });
}
