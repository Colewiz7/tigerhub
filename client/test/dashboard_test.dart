/// The dashboard as module instances, and the migration into it.
///
/// Stage one of `docs/modular-dashboard-spec.md`. The model is the easy half.
/// The half worth testing is the migration: anyone using the app already has
/// four cards in an order they chose, some possibly hidden, and that has to
/// survive exactly. Losing it would cost them their setup to gain a capability
/// they have not asked for yet.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // Cleared explicitly: reassigning the platform does not reliably reset it,
    // and one test's saved dashboard leaking into the next made two of these
    // pass or fail depending on order.
    for (final key in ['dashboard_v2', 'cards', 'cards_hidden']) {
      await ResponseCache.instance.writeOrder(key, const []);
    }
  });

  group('migration from the old four string ids', () {
    test('keeps the order the user chose', () {
      final cards = migrateLegacy(
        ['housing', 'chefs', 'dining', 'events'],
        const [],
      );
      expect(
        cards.map((c) => c.type),
        [
          ModuleType.mailingAddress,
          ModuleType.visitingChefs,
          ModuleType.diningStatus,
          ModuleType.generalEvents,
        ],
      );
    });

    test('keeps what was hidden hidden', () {
      final cards = migrateLegacy(
        ['dining', 'events', 'chefs', 'housing'],
        ['chefs'],
      );
      final chefs =
          cards.firstWhere((c) => c.type == ModuleType.visitingChefs);
      expect(chefs.hidden, isTrue);
      expect(cards.where((c) => c.hidden).length, 1,
          reason: 'hiding one card hid others too');
    });

    test('a partial saved list still yields a whole dashboard', () {
      // Someone who removed a card should not end up with a dashboard that
      // cannot offer it back.
      final cards = migrateLegacy(['events'], const []);
      expect(cards.length, 4);
      expect(cards.first.type, ModuleType.generalEvents,
          reason: 'their explicit order should still lead');
    });

    test('an unknown id is dropped rather than guessed at', () {
      final cards = migrateLegacy(['dining', 'weather', 'events'], const []);
      expect(cards.length, 4);
      expect(cards.map((c) => c.type), isNot(contains(null)));
    });

    test('a duplicate id is not placed twice', () {
      final cards = migrateLegacy(['dining', 'dining', 'events'], const []);
      expect(cards.where((c) => c.type == ModuleType.diningStatus).length, 1);
    });

    test('every instance gets a distinct id', () {
      final cards = migrateLegacy(
        ['dining', 'events', 'chefs', 'housing'],
        const [],
      );
      expect(cards.map((c) => c.id).toSet().length, cards.length);
    });
  });

  group('sizes', () {
    test('a module only offers sizes its content survives', () {
      // Mailing Address has nothing meaningful to say in one line, and the map
      // needs the width.
      expect(supportedSizes[ModuleType.mailingAddress], [CardSize.standard]);
      expect(supportedSizes[ModuleType.campusMap], [CardSize.wide]);
    });

    test('every module declares at least one size', () {
      for (final type in ModuleType.values) {
        expect(supportedSizes[type], isNotNull, reason: '${type.id} has none');
        expect(supportedSizes[type], isNotEmpty);
      }
    });

    test('wide asks for two columns, the rest for one', () {
      expect(CardSize.wide.columns, 2);
      expect(CardSize.compact.columns, 1);
      expect(CardSize.standard.columns, 1);
    });

    test('an unsupported saved size falls back instead of throwing', () {
      // A build that offered a size, then stopped, must not strand the card.
      final card = CardInstance.fromJson({
        'id': 'x',
        'type': 'mailing_address',
        'size': 'compact',
      });
      expect(card, isNotNull);
      expect(card!.size, CardSize.standard);
    });

    test('a type from a newer build is skipped, not fatal', () {
      expect(CardInstance.fromJson({'id': 'x', 'type': 'horoscope'}), isNull);
    });
  });

  group('round trip', () {
    test('an instance survives being saved and loaded', () async {
      const cards = [
        CardInstance(
          id: 'club-1',
          type: ModuleType.clubEvents,
          size: CardSize.wide,
          scope: 'FOODSHARE',
        ),
        CardInstance(
          id: 'dining-0',
          type: ModuleType.diningStatus,
          size: CardSize.compact,
          hidden: true,
        ),
      ];

      await DashboardStore.save(cards);
      final loaded = await DashboardStore.load();

      expect(loaded.length, 2);
      expect(loaded.first.scope, 'FOODSHARE',
          reason: 'the scope is what makes two of one type different');
      expect(loaded.first.size, CardSize.wide);
      expect(loaded.last.hidden, isTrue);
    });

    test('two instances of one type stay distinct', () async {
      const cards = [
        CardInstance(id: 'club-1', type: ModuleType.clubEvents, scope: 'RITBKC'),
        CardInstance(id: 'club-2', type: ModuleType.clubEvents, scope: 'NEWMAN'),
      ];
      await DashboardStore.save(cards);
      final loaded = await DashboardStore.load();

      expect(loaded.map((c) => c.scope), ['RITBKC', 'NEWMAN']);
      expect(loaded.map((c) => c.id).toSet().length, 2);
    });

    test('a first run with nothing saved gets the shipped four', () async {
      final loaded = await DashboardStore.load();
      expect(loaded.map((c) => c.type),
          defaultDashboard.map((c) => c.type).toList());
    });

    test('migrating writes the new format, so it only happens once', () async {
      await ResponseCache.instance
          .writeOrder('cards', ['events', 'dining', 'chefs', 'housing']);

      await DashboardStore.load();

      // Leaving the old keys authoritative would mean scope and size had
      // nowhere to live until the user happened to edit something.
      final saved = await ResponseCache.instance.readOrder('dashboard_v2');
      expect(saved, isNotEmpty);

      // And the second load comes from the new format, not the old one.
      await ResponseCache.instance.writeOrder('cards', const []);
      final again = await DashboardStore.load();
      expect(again.first.type, ModuleType.generalEvents);
    });

    test('the old format is picked up when the new one is absent', () async {
      await ResponseCache.instance
          .writeOrder('cards', ['housing', 'dining', 'events', 'chefs']);
      await ResponseCache.instance.writeOrder('cards_hidden', ['events']);

      final loaded = await DashboardStore.load();

      expect(loaded.first.type, ModuleType.mailingAddress);
      expect(
        loaded.firstWhere((c) => c.type == ModuleType.generalEvents).hidden,
        isTrue,
      );
    });

    test('one unreadable entry does not take the rest with it', () async {
      await ResponseCache.instance.writeOrder('dashboard_v2', [
        '{"id":"a","type":"dining_status"}',
        'not json at all',
        '{"id":"b","type":"general_events"}',
      ]);

      final loaded = await DashboardStore.load();
      expect(loaded.length, 2);
    });
  });
}
