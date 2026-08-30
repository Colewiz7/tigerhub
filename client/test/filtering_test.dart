/// Event filtering and preference persistence.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/event_filter.dart';
import 'package:tigerhub/services/filter_profiles.dart';
import 'package:tigerhub/services/preferences.dart';

CampusEvent event(
  String title, {
  String organizer = 'Dodgeball Club',
  String key = 'DODGE',
  int day = 1,
}) =>
    CampusEvent(
      uid: '$title-$day',
      source: 'campusgroups',
      title: title,
      organizer: organizer,
      organizerKey: key,
      startsAt: DateTime(2026, 9, day, 18),
      endsAt: DateTime(2026, 9, day, 20),
    );

void main() {
  // ResponseCache is a singleton that binds to whatever platform exists when
  // it is first touched, so the store is installed once and cleared between
  // tests rather than replaced.
  final store = InMemorySharedPreferencesAsync.empty();

  setUpAll(() => SharedPreferencesAsyncPlatform.instance = store);

  setUp(() async {
    await store.clear(const ClearPreferencesParameters(filter: PreferencesFilters()),
        SharedPreferencesOptions());
    Preferences.instance.resetForTests();
  });

  group('preferences persist across a restart', () {
    test('muted organizers survive reload', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setMuted('FOODSHARE', true);
      await prefs.setMuted('CRU', true);

      // Simulate a restart: same storage, fresh in-memory state.
      prefs.resetForTests();
      await prefs.load();

      expect(prefs.mutedOrganizers, {'FOODSHARE', 'CRU'});
    });

    test('unmuting survives reload', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setMuted('FOODSHARE', true);
      await prefs.setMuted('FOODSHARE', false);

      prefs.resetForTests();
      await prefs.load();
      expect(prefs.mutedOrganizers, isEmpty);
    });

    test('edited keywords survive reload', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['bingo', 'quiz']);
      await prefs.setBoostKeywords(['dodgeball']);

      prefs.resetForTests();
      await prefs.load();
      expect(prefs.hideKeywords, ['bingo', 'quiz']);
      expect(prefs.boostKeywords, ['dodgeball']);
    });

    test('an emptied keyword list stays empty rather than reverting to defaults',
        () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords([]);

      prefs.resetForTests();
      await prefs.load();
      // Clearing the list is a deliberate choice, not an absence of one.
      expect(prefs.hideKeywords, isEmpty);
      expect(prefs.hideKeywords, isNot(defaultHideKeywords));
    });

    test('keywords are lowercased and deduplicated', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['Bingo', 'bingo', '  QUIZ  ', '']);
      expect(prefs.hideKeywords, ['bingo', 'quiz']);
    });

    test('the keyword toggle survives reload', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setKeywordRulesEnabled(false);

      prefs.resetForTests();
      await prefs.load();
      expect(prefs.keywordRulesEnabled, isFalse);
    });
  });

  group('organizer muting', () {
    test('a muted organizer with zero remaining events leaves no group header',
        () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords([]);
      await prefs.setMuted('FOODSHARE', true);

      final result = filterEvents([
        event('Pantry', organizer: 'RIT FoodShare', key: 'FOODSHARE'),
        event('Closet', organizer: 'RIT FoodShare', key: 'FOODSHARE', day: 2),
        event('Dodgeball night'),
      ], prefs);

      // The whole point: an empty header would be worse than nothing.
      expect(result.groups.map((g) => g.organizer), ['Dodgeball Club']);
      expect(result.hiddenTotal, 2,
          reason: 'muted events must still be counted as recoverable');
    });

    test('a partially muted feed keeps the surviving group', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords([]);
      await prefs.setMuted('CRU', true);

      final result = filterEvents([
        event('Bible study', organizer: 'Cru', key: 'CRU'),
        event('Dodgeball night'),
      ], prefs);

      expect(result.groups.length, 1);
      expect(result.hiddenTotal, 1);
    });
  });

  group('keyword rules', () {
    test('hidden keywords remove an event but keep it counted', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['info session']);

      final result = filterEvents([
        event('Tiger Tutor Info Session'),
        event('Dodgeball tournament', day: 2),
      ], prefs);

      expect(result.groups.single.visible.length, 1);
      expect(result.groups.single.hiddenCount, 1);
      expect(result.hiddenTotal, 1);
    });

    test('expanding hidden reveals exactly the filtered events', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['workshop']);

      final result = filterEvents([
        event('Resume workshop'),
        event('Pottery workshop', day: 2),
        event('Free pizza', day: 3),
      ], prefs);

      final hiddenTitles =
          result.groups.single.hidden.map((e) => e.event.title).toList();
      expect(hiddenTitles, ['Resume workshop', 'Pottery workshop']);
      expect(result.groups.single.visible.map((e) => e.event.title), ['Free pizza']);
    });

    test('boosted events sort to the top of their group', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords([]);
      await prefs.setBoostKeywords(['free']);

      final result = filterEvents([
        event('Regular meeting', day: 1),
        event('Free ice cream', day: 5),
      ], prefs);

      final visible = result.groups.single.visible;
      expect(visible.first.event.title, 'Free ice cream');
      expect(visible.first.boosted, isTrue);
      expect(visible.last.boosted, isFalse);
    });

    test('disabling keyword rules stops both hiding and boosting', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['workshop']);
      await prefs.setKeywordRulesEnabled(false);

      final result = filterEvents([
        event('Resume workshop'),
        event('Free pizza', day: 2),
      ], prefs);

      expect(result.hiddenTotal, 0);
      expect(result.groups.single.visible.every((e) => !e.boosted), isTrue);
    });

    test('muting takes precedence over a boost keyword', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setMuted('DODGE', true);
      await prefs.setBoostKeywords(['free']);

      final result = filterEvents([event('Free pizza')], prefs);
      expect(result.groups, isEmpty);
      expect(result.hiddenTotal, 1);
    });
  });

  group('hidden counts are accurate', () {
    test('total equals the sum across every group, including dropped ones',
        () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['seminar']);
      await prefs.setMuted('CRU', true);

      final events = [
        event('Dodgeball night'),
        event('Physics seminar', day: 2),
        event('Bible study', organizer: 'Cru', key: 'CRU'),
        event('Worship', organizer: 'Cru', key: 'CRU', day: 2),
      ];
      final result = filterEvents(events, prefs);

      final visible = result.groups.fold<int>(0, (n, g) => n + g.visible.length);
      expect(visible + result.hiddenTotal, events.length,
          reason: 'every event is either visible or counted as hidden');
      expect(result.hiddenTotal, 3);
    });

    test('nothing is hidden when no rules match', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setHideKeywords(['nonexistent']);

      final result = filterEvents([event('Dodgeball night')], prefs);
      expect(result.hiddenTotal, 0);
      expect(result.groups.single.hidden, isEmpty);
    });
  });

  _profiles();

  group('organizer facets for the settings list', () {
    test('counts per organizer, busiest first', () {
      final facets = organizerFacets([
        event('a', organizer: 'RIT FoodShare', key: 'FOODSHARE'),
        event('b', organizer: 'RIT FoodShare', key: 'FOODSHARE', day: 2),
        event('c'),
      ]);
      expect(facets.first.name, 'RIT FoodShare');
      expect(facets.first.count, 2);
      expect(facets.first.key, 'FOODSHARE');
      expect(facets.last.count, 1);
    });
  });
}

void _profiles() {
  group('filter profiles', () {
    setUp(() => Preferences.instance.resetForTests());

    test('applying a preset replaces both rule lists in one go', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      final fun = profileById('free_and_fun')!;
      await prefs.applyProfile(fun.hide, fun.boost,
          keywordsEnabled: fun.keywordsEnabled);

      expect(prefs.boostKeywords, contains('ice cream'));
      expect(prefs.hideKeywords, contains('career fair'));
      expect(activeProfile(prefs)?.id, 'free_and_fun');
    });

    test('a preset survives a restart', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      final academic = profileById('academic')!;
      await prefs.applyProfile(academic.hide, academic.boost,
          keywordsEnabled: academic.keywordsEnabled);

      prefs.resetForTests();
      await prefs.load();
      expect(activeProfile(prefs)?.id, 'academic');
    });

    test('editing a rule forks to custom rather than mutating the preset',
        () async {
      final prefs = Preferences.instance;
      await prefs.load();
      final fun = profileById('free_and_fun')!;
      await prefs.applyProfile(fun.hide, fun.boost,
          keywordsEnabled: fun.keywordsEnabled);
      expect(activeProfile(prefs)?.id, 'free_and_fun');

      await prefs.setBoostKeywords([...prefs.boostKeywords, 'dodgeball']);
      expect(activeProfile(prefs), isNull,
          reason: 'the rules are no longer the preset, so do not claim it is');
      // The preset itself is untouched and can be reapplied.
      expect(profileById('free_and_fun')!.boost, isNot(contains('dodgeball')));
    });

    test('Everything turns the keyword rules off but keeps organizer mutes',
        () async {
      final prefs = Preferences.instance;
      await prefs.load();
      await prefs.setMuted('FOODSHARE', true);
      final all = profileById('everything')!;
      await prefs.applyProfile(all.hide, all.boost,
          keywordsEnabled: all.keywordsEnabled);

      expect(prefs.keywordRulesEnabled, isFalse);
      expect(prefs.mutedOrganizers, contains('FOODSHARE'),
          reason: 'a profile is about keywords, not about who you muted');
    });

    test('the fun preset actually matches the stated taste', () async {
      final prefs = Preferences.instance;
      await prefs.load();
      final fun = profileById('free_and_fun')!;
      await prefs.applyProfile(fun.hide, fun.boost,
          keywordsEnabled: fun.keywordsEnabled);

      final result = filterEvents([
        event('Free ice cream on the quarter mile'),
        event('Dodgeball tournament', day: 2),
        event('Resume workshop', day: 3),
        event('Bible study', day: 4),
      ], prefs);

      final visible =
          result.groups.single.visible.map((e) => e.event.title).toList();
      expect(visible.first, contains('ice cream'), reason: 'boosted to the top');
      expect(visible, isNot(contains('Resume workshop')));
      expect(visible, isNot(contains('Bible study')));
      // Hidden, not gone.
      expect(result.hiddenTotal, 2);
    });
  });
}
