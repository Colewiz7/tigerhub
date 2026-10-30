/// The setup draft: nothing is stored until it is applied, and applying is
/// additive.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/filter_profiles.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/services/setup_draft.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

Future<void> _clear() async {
  for (final key in const [
    'housing_area',
    'housing_unit',
    'dashboard_v2',
    'cards',
    'cards_hidden',
    'color_scheme',
    'pinned_dining',
    'hidden_dining',
    'hidden_dining_groups',
    'muted_organizers',
    'hide_keywords',
    'boost_keywords',
    'keyword_rules_enabled',
    'setup_seen',
  ]) {
    await ResponseCache.instance.writeOrder(key, const []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SchemeController scheme;
  final prefs = Preferences.instance;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final file = jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>;
    StaticConfig.overrideForTesting({'dining_groups': file});
    await _clear();
    prefs.resetForTests();
    await prefs.load();
    scheme = SchemeController();
    addTearDown(scheme.dispose);
  });

  List<CardInstance> visible(List<CardInstance> cards) => [
    for (final c in cards)
      if (!c.hidden) c,
  ];

  group('the Today plan', () {
    test('starts from the default cards', () {
      final plan = TodayPlan.of(base: defaultDashboard, draft: SetupDraft());
      expect(visible(plan.cards).map((c) => c.id), ['dining-0', 'events-0', 'chefs-0', 'housing-0']);
    });

    test('picked spots keep Eat now on, a new home turns Shuttles and Package pickup on', () {
      final draft = SetupDraft()
        ..toggleSpot('21')
        ..setArea('global-village');
      final plan = TodayPlan.of(base: defaultDashboard, draft: draft);
      final types = visible(plan.cards).map((c) => c.type);
      expect(types, containsAll([ModuleType.diningStatus, ModuleType.shuttles, ModuleType.packagePickup]));
    });

    test('Shuttles and Package pickup stay off without a home', () {
      final plan = TodayPlan.of(base: defaultDashboard, draft: SetupDraft());
      final types = visible(plan.cards).map((c) => c.type);
      expect(types, isNot(contains(ModuleType.shuttles)));
      expect(types, isNot(contains(ModuleType.packagePickup)));
    });

    test('Eat now comes back when spots are picked and it was taken off', () {
      final base = [for (final c in defaultDashboard) c.type == ModuleType.diningStatus ? c.copyWith(hidden: true) : c];
      final plan = TodayPlan.of(base: base, draft: SetupDraft()..toggleSpot('21'));
      expect(visible(plan.cards).map((c) => c.type), contains(ModuleType.diningStatus));
    });

    test('each followed club gets a Club events card scoped to it', () {
      final draft = SetupDraft()
        ..followClub('sg', 'Student Government')
        ..followClub('chess', 'Chess Club');
      final plan = TodayPlan.of(base: defaultDashboard, draft: draft);
      final clubs = plan.cards.where((c) => c.type == ModuleType.clubEvents).toList();
      expect([for (final c in clubs) c.id], ['club-chess', 'club-sg']);
      expect([for (final c in clubs) c.scope], ['chess', 'sg']);
    });

    test('plain toggles add Calendar, Academic dates and Campus map', () {
      final draft = SetupDraft()
        ..setCard(ModuleType.calendar, true)
        ..setCard(ModuleType.academicDates, true)
        ..setCard(ModuleType.campusMap, true);
      final plan = TodayPlan.of(base: defaultDashboard, draft: draft);
      expect(visible(plan.cards).map((c) => c.type), containsAll([ModuleType.calendar, ModuleType.academicDates, ModuleType.campusMap]));
    });

    test('Facility hours is not offered', () {
      final plan = TodayPlan.of(base: defaultDashboard, draft: SetupDraft());
      expect(plan.rows.map((r) => r.row.type), isNot(contains(ModuleType.facilityHours)));
    });

    test('turning a card off hides it and keeps its instance, scope, size and place', () {
      final base = [
        ...defaultDashboard,
        const CardInstance(id: 'facility-0', type: ModuleType.facilityHours, size: CardSize.compact, scope: 'Pool'),
        const CardInstance(id: 'club-sg', type: ModuleType.clubEvents, scope: 'sg', size: CardSize.wide),
      ];
      final draft = SetupDraft()
        ..setCard(ModuleType.visitingChefs, false)
        ..setCard(ModuleType.generalEvents, false)
        ..unfollowClub('sg');
      final plan = TodayPlan.of(base: base, draft: draft);
      expect(plan.cards.length, base.length);
      expect([for (final c in plan.cards) c.id], [for (final c in base) c.id]);
      final chefs = plan.cards.firstWhere((c) => c.id == 'chefs-0');
      expect(chefs.hidden, isTrue);
      final club = plan.cards.firstWhere((c) => c.id == 'club-sg');
      expect((club.hidden, club.scope, club.size), (true, 'sg', CardSize.wide));
      // an untouched card is the very same
      expect(plan.cards.firstWhere((c) => c.id == 'facility-0'), base[4]);
    });

    test('turning a hidden card on shows the same instance again', () {
      final base = [
        ...defaultDashboard,
        const CardInstance(id: 'calendar-3', type: ModuleType.calendar, size: CardSize.wide, hidden: true),
      ];
      final plan = TodayPlan.of(base: base, draft: SetupDraft()..setCard(ModuleType.calendar, true));
      expect(plan.cards.length, base.length);
      expect(plan.cards.last.hidden, isFalse);
      expect(plan.cards.last.id, 'calendar-3');
    });

    test('a prefilled draft changes nothing, even with a home and spots', () async {
      await prefs.setHome(area: 'global-village');
      await prefs.togglePinned(23);
      // a home and spots that were set before are not new
      final again = SetupDraft.prefilled(prefs: prefs, scheme: AppScheme.espresso, dashboard: defaultDashboard);
      expect(TodayPlan.of(base: defaultDashboard, draft: again).cards, defaultDashboard);
      expect(again.homeIsNew, isFalse);
      expect((again..setArea('residence-halls')).homeIsNew, isTrue);
    });

    test('a re-run does not bring back Shuttles that were taken off', () async {
      await prefs.setHome(area: 'global-village');
      final base = [
        ...defaultDashboard,
        const CardInstance(id: 'shuttles-0', type: ModuleType.shuttles, size: CardSize.compact, hidden: true),
      ];
      final draft = SetupDraft.prefilled(prefs: prefs, scheme: AppScheme.espresso, dashboard: base);
      final plan = TodayPlan.of(base: base, draft: draft);
      expect(plan.cards.firstWhere((c) => c.id == 'shuttles-0').hidden, isTrue);
    });
  });

  group('applying', () {
    test('an empty draft changes nothing but still marks setup answered', () async {
      final before = (prefs.hideKeywords, prefs.boostKeywords, prefs.pinnedDining, prefs.homeArea);
      await applyDraft(SetupDraft(), prefs: prefs, scheme: scheme);
      expect((prefs.hideKeywords, prefs.boostKeywords, prefs.pinnedDining, prefs.homeArea), before);
      expect(prefs.setupSeen, isTrue);
      expect(await DashboardStore.load(), defaultDashboard);
    });

    test('skipping Events keeps the keyword defaults', () async {
      final draft = SetupDraft()
        ..setArea('global-village')
        ..toggleSpot('21');
      await applyDraft(draft, prefs: prefs, scheme: scheme);
      expect(prefs.hideKeywords, defaultHideKeywords);
      expect(prefs.boostKeywords, defaultBoostKeywords);
      expect(prefs.keywordRulesEnabled, isTrue);
    });

    test('nothing is stored until it is applied', () async {
      final draft = SetupDraft()
        ..setArea('global-village')
        ..setUnit('GV 400')
        ..toggleSpot('23')
        ..setHideDormSide(true)
        ..setProfile('quiet');
      expect(prefs.homeArea, isNull);
      expect(prefs.pinnedDining, isEmpty);
      expect(prefs.hiddenDiningGroups, isEmpty);
      expect(prefs.setupSeen, isFalse);
      expect(draft.profile, 'quiet');
    });

    test('every answer lands', () async {
      final draft = SetupDraft()
        ..setScheme(AppScheme.slate)
        ..setArea('global-village')
        ..setUnit('GV 400 1020')
        ..toggleSpot('23')
        ..toggleSpot('32')
        ..setHideDormSide(true)
        ..setProfile('academic')
        ..followClub('sg', 'Student Government')
        ..setCard(ModuleType.calendar, true);
      await applyDraft(draft, prefs: prefs, scheme: scheme);

      expect(scheme.choice, AppScheme.slate);
      expect(prefs.homeArea, 'global-village');
      expect(prefs.homeUnit, 'GV 400 1020');
      expect(prefs.pinnedDining, {'23', '32'});
      expect(prefs.hiddenDiningGroups, {'dorm_side'});
      expect(activeProfile(prefs)?.id, 'academic');
      final cards = await DashboardStore.load();
      expect(visible(cards).map((c) => c.id), containsAll(['club-sg', 'shuttles-0', 'package_pickup-0']));
      expect(cards.where((c) => c.type == ModuleType.calendar && !c.hidden), hasLength(1));
      expect(prefs.setupSeen, isTrue);
    });

    test('spots removed in a re-run are unpinned', () async {
      await prefs.togglePinned(23);
      await prefs.togglePinned(32);
      final draft = SetupDraft.prefilled(prefs: prefs, scheme: AppScheme.espresso, dashboard: defaultDashboard)..toggleSpot('23');
      await applyDraft(draft, prefs: prefs, scheme: scheme);
      expect(prefs.pinnedDining, {'32'});
    });

    test('a pick on a hidden place pins it and shows it', () async {
      await prefs.toggleHidden(23);
      await applyDraft(SetupDraft()..toggleSpot('23'), prefs: prefs, scheme: scheme);
      expect(prefs.pinnedDining, {'23'});
      expect(prefs.hiddenDining, isEmpty);
    });

    test('saving tells Today to reload', () async {
      var heard = 0;
      void listener() => heard++;
      DashboardStore.changes.addListener(listener);
      addTearDown(() => DashboardStore.changes.removeListener(listener));
      await applyDraft(SetupDraft()..setCard(ModuleType.calendar, true), prefs: prefs, scheme: scheme);
      expect(heard, 1);
    });

    test('Today saving its own order stays quiet', () async {
      var heard = 0;
      void listener() => heard++;
      DashboardStore.changes.addListener(listener);
      addTearDown(() => DashboardStore.changes.removeListener(listener));
      await DashboardStore.save(defaultDashboard);
      expect(heard, 0);
    });

    test('a re-run Save with nothing edited leaves the app as it was', () async {
      await prefs.setHome(area: 'global-village', unit: 'GV 1');
      await prefs.togglePinned(23);
      await prefs.applyProfile(['a'], ['b'], keywordsEnabled: true);
      final base = [
        ...defaultDashboard,
        const CardInstance(id: 'facility-0', type: ModuleType.facilityHours, scope: 'Pool', size: CardSize.compact),
      ];
      await DashboardStore.save(base);
      final draft = SetupDraft.prefilled(prefs: prefs, scheme: AppScheme.mocha, dashboard: base);
      await applyDraft(draft, prefs: prefs, scheme: scheme);
      expect(prefs.hideKeywords, ['a']);
      expect(prefs.pinnedDining, {'23'});
      expect(prefs.homeUnit, 'GV 1');
      expect([for (final c in await DashboardStore.load()) c.toJson()], [for (final c in base) c.toJson()]);
    });
  });

  group('existing data', () {
    test('a fresh phone has none', () async {
      expect(await hasExistingData(), isFalse);
    });

    for (final (name, write) in <(String, Future<void> Function())>[
      ('a home', () => prefs.setHome(area: 'global-village')),
      ('a pinned place', () => prefs.togglePinned(23)),
      ('a muted organizer', () => prefs.setMuted('sg', true)),
      ('edited rules', () => prefs.setHideKeywords(['x'])),
      ('a saved dashboard', () => DashboardStore.save(defaultDashboard)),
      ('a stored scheme', () => SchemeController().select(AppScheme.mocha)),
      ('legacy cards', () => ResponseCache.instance.writeOrder('cards', ['dining'])),
    ]) {
      test('$name counts', () async {
        await write();
        expect(await hasExistingData(), isTrue);
      });
    }
  });
}
