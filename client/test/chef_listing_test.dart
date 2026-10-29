/// Chefs disappear 30 minutes after their slot ends.
///
/// Runs under the CI TZ matrix. Every instant is absolute, so the answer must
/// not move with the device zone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/chef_listing.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'golden_harness.dart';

MenuItem _chef(int id, DateTime? start, DateTime? end) => MenuItem(id: id, name: 'Chef $id', locationName: 'RITZ', startsAt: start, endsAt: end);

Result<Collection<MenuItem>> _ok(List<MenuItem> data) => Result(value: ChefCollection(data: data, stale: false), state: DataState.ok);

Future<void> _pump(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
  await tester.pumpWidget(MaterialApp(theme: AppTheme.from(scheme), home: Scaffold(body: SingleChildScrollView(child: card))));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(RitClock.reset);

  final end = CampusTime.wall(2026, 10, 14, 14);
  final start = CampusTime.wall(2026, 10, 14, 11);

  group('chefStillListed', () {
    test('end plus 29:59 is shown, plus 30:00 is hidden', () {
      final chef = _chef(1, start, end);
      expect(chefStillListed(chef, now: end.add(const Duration(minutes: 29, seconds: 59))), isTrue);
      expect(chefStillListed(chef, now: end.add(const Duration(minutes: 30))), isFalse);
    });

    test('a slot still running or not started is shown', () {
      final chef = _chef(1, start, end);
      expect(chefStillListed(chef, now: start.subtract(const Duration(hours: 2))), isTrue);
      expect(chefStillListed(chef, now: end.subtract(const Duration(minutes: 1))), isTrue);
    });

    test('a chef with no time stays all day', () {
      final chef = _chef(1, null, null);
      expect(chefStillListed(chef, now: CampusTime.wall(2026, 10, 14, 23, 59)), isTrue);
    });

    test('a start with no end stays', () {
      expect(chefStillListed(_chef(1, start, null), now: CampusTime.wall(2026, 10, 14, 23)), isTrue);
    });

    test('an overnight slot lasts past midnight', () {
      final late = CampusTime.wall(2026, 10, 14, 22);
      final past = CampusTime.wall(2026, 10, 15, 1);
      final chef = _chef(1, late, past);
      expect(chefStillListed(chef, now: CampusTime.wall(2026, 10, 15, 1, 29)), isTrue);
      expect(chefStillListed(chef, now: CampusTime.wall(2026, 10, 15, 1, 30)), isFalse);
      // an end stamped on the start's date still reads as next day
      final sameDay = _chef(2, late, CampusTime.wall(2026, 10, 14, 1));
      expect(chefStillListed(sameDay, now: CampusTime.wall(2026, 10, 15, 0, 45)), isTrue);
      expect(chefStillListed(sameDay, now: CampusTime.wall(2026, 10, 15, 1, 30)), isFalse);
    });

    test('same cutoff for a slot written in any zone offset', () {
      final instant = DateTime.utc(2026, 10, 14, 18);
      final cutoff = instant.add(chefGrace);
      for (final stamp in ['2026-10-14T14:00:00-04:00', '2026-10-14T11:00:00-07:00', '2026-10-15T03:00:00+09:00', '2026-10-14T18:00:00Z']) {
        final chef = _chef(1, null, DateTime.parse(stamp));
        expect(chefStillListed(chef, now: cutoff.subtract(const Duration(seconds: 1))), isTrue, reason: stamp);
        expect(chefStillListed(chef, now: cutoff), isFalse, reason: stamp);
      }
    });

    test('dst change does not shift the cutoff', () {
      // slot ends 00:45 EDT on 1 Nov, grace crosses the fall back at 06:00 UTC
      final ends = CampusTime.wall(2026, 11, 1, 0, 45);
      final chef = _chef(1, null, ends);
      expect(chefStillListed(chef, now: DateTime.utc(2026, 11, 1, 5, 14)), isTrue);
      expect(chefStillListed(chef, now: DateTime.utc(2026, 11, 1, 5, 15)), isFalse);
    });

    test('uses the pinned clock by default', () {
      final chef = _chef(1, start, end);
      RitClock.pin(end.add(const Duration(minutes: 29)));
      expect(chefStillListed(chef), isTrue);
      RitClock.pin(end.add(const Duration(minutes: 31)));
      expect(chefStillListed(chef), isFalse);
    });
  });

  group('counts', () {
    final chefs = [
      _chef(1, start, end),
      _chef(2, CampusTime.wall(2026, 10, 14, 16), CampusTime.wall(2026, 10, 14, 19)),
      _chef(3, null, null),
    ];

    test('listedChefs keeps only the live ones', () {
      expect(listedChefs(chefs, now: CampusTime.wall(2026, 10, 14, 15)).map((c) => c.id), [2, 3]);
      expect(listedChefs(chefs, now: CampusTime.wall(2026, 10, 14, 12)).map((c) => c.id), [1, 2, 3]);
    });

    test('compact value counts only listed chefs', () {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15));
      expect(chefsCompactValue(_ok(chefs)), '2 today');
      RitClock.pin(CampusTime.wall(2026, 10, 14, 19, 30));
      expect(chefsCompactValue(_ok(chefs)), '1 today');
    });

    test('all hidden reads no more chefs, a quiet day none today, an outage unavailable', () {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 22));
      final ended = _ok([chefs[0], chefs[1]]);
      expect(chefsCompactValue(ended), 'No more chefs');
      expect(chefsCompactValue(_ok(const [])), 'None today');
      final down = Result<Collection<MenuItem>>(value: ChefCollection(data: const [], stale: false, availability: Availability.unavailable), state: DataState.ok);
      expect(chefsCompactValue(down), 'Unavailable');
    });
  });

  group('next cutoff', () {
    test('is the soonest end plus grace still ahead', () {
      final chefs = [
        _chef(1, start, end),
        _chef(2, CampusTime.wall(2026, 10, 14, 16), CampusTime.wall(2026, 10, 14, 19)),
        _chef(3, null, null),
      ];
      expect(nextChefCutoff(chefs, now: CampusTime.wall(2026, 10, 14, 12)), end.add(chefGrace));
      expect(nextChefCutoff(chefs, now: CampusTime.wall(2026, 10, 14, 15)), CampusTime.wall(2026, 10, 14, 19, 30));
      expect(nextChefCutoff(chefs, now: CampusTime.wall(2026, 10, 14, 20)), isNull);
      expect(nextChefCutoff([_chef(3, null, null)]), isNull);
    });
  });

  group('nextChefLine', () {
    final today = DateTime.utc(2026, 10, 14);
    UpcomingChef next(DateTime date) => UpcomingChef(date: date, name: 'Chef Lin', locationName: 'Gracie’s');

    test('tomorrow is a word, later days are dated', () {
      expect(nextChefLine(next(DateTime.utc(2026, 10, 15)), today), 'Next: Tomorrow · Chef Lin · Gracie’s');
      expect(nextChefLine(next(DateTime.utc(2026, 10, 18)), today), 'Next: Sun, Oct 18 · Chef Lin · Gracie’s');
    });

    test('a missing place is left out', () {
      final line = nextChefLine(UpcomingChef(date: DateTime.utc(2026, 10, 15), name: 'Chef Lin', locationName: ''), today);
      expect(line, 'Next: Tomorrow · Chef Lin');
    });
  });

  group('next chef on the card', () {
    final chef = _chef(1, CampusTime.wall(2026, 10, 14, 11), CampusTime.wall(2026, 10, 14, 14));
    final next = UpcomingChef(date: DateTime.utc(2026, 10, 15), name: 'Chef Lin', locationName: 'Gracie’s');
    Result<Collection<MenuItem>> ended(UpcomingChef? next) => Result(value: ChefCollection(data: [chef], stale: false, next: next), state: DataState.ok);

    testWidgets('shows under No more chefs today', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15));
      await _pump(tester, VisitingChefsCard(result: ended(next)));
      expect(find.text('No more chefs today'), findsOneWidget);
      expect(find.text('Next: Tomorrow · Chef Lin · Gracie’s'), findsOneWidget);
    });

    testWidgets('is absent when no next chef is known', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15));
      await _pump(tester, VisitingChefsCard(result: ended(null)));
      expect(find.text('No more chefs today'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });
  });

  group('timer', () {
    final chef = _chef(1, CampusTime.wall(2026, 10, 14, 11), CampusTime.wall(2026, 10, 14, 14));

    testWidgets('hides the chef at the cutoff with no data refresh', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 13, 50));
      await _pump(tester, VisitingChefsCard(result: _ok([chef])));
      expect(find.text('Chef 1'), findsOneWidget);

      // the slot ends first, which rearms for the cutoff
      RitClock.pin(CampusTime.wall(2026, 10, 14, 14));
      await tester.pump(const Duration(minutes: 10));
      expect(find.text('Chef 1'), findsOneWidget);

      // the clock reaches the cutoff and the one shot fires
      RitClock.pin(CampusTime.wall(2026, 10, 14, 14, 30));
      await tester.pump(const Duration(minutes: 29));
      expect(find.text('Chef 1'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Chef 1'), findsNothing);
      expect(find.text('No more chefs today'), findsOneWidget);
      // nothing left to arm, so a ticking timer would fail the test here
    });

    testWidgets('the compact card flips at the cutoff too', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 13, 50));
      await _pump(tester, VisitingChefsCard(compact: true, result: _ok([chef])));
      expect(find.text('1 today'), findsOneWidget);
      RitClock.pin(CampusTime.wall(2026, 10, 14, 14, 30));
      await tester.pump(const Duration(minutes: 40));
      expect(find.text('No more chefs'), findsOneWidget);
    });

    testWidgets('rearms for the next chef after one drops', (tester) async {
      final late = _chef(2, null, CampusTime.wall(2026, 10, 14, 16));
      RitClock.pin(CampusTime.wall(2026, 10, 14, 13, 50));
      await _pump(tester, VisitingChefsCard(result: _ok([chef, late])));
      RitClock.pin(CampusTime.wall(2026, 10, 14, 14, 30));
      await tester.pump(const Duration(minutes: 40));
      expect(find.text('Chef 1'), findsNothing);
      expect(find.text('Chef 2'), findsOneWidget);
      RitClock.pin(CampusTime.wall(2026, 10, 14, 16, 30));
      await tester.pump(const Duration(minutes: 120));
      expect(find.text('Chef 2'), findsNothing);
    });

    testWidgets('a new result rearms the timer', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 13, 50));
      await _pump(tester, VisitingChefsCard(result: _ok(const [])));
      // same tree, so this is didUpdateWidget on the live state
      await _pump(tester, VisitingChefsCard(result: _ok([chef])));
      RitClock.pin(CampusTime.wall(2026, 10, 14, 14, 30));
      await tester.pump(const Duration(minutes: 40));
      expect(find.text('Chef 1'), findsNothing);
    });

    testWidgets('dispose leaves no pending timer', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 13, 50));
      await _pump(tester, VisitingChefsCard(result: _ok([chef])));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      // the harness fails the test if the armed timer is still pending
    });
  });

  group('compact copy', () {
    testWidgets('no more chefs fits one line at 1x in the narrowest paired half cell', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 22));
      // two up starts at 360, where a card is 360 / 2 - 16 margin - 5 gap wide
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));
      final theme = AppTheme.from(scheme);
      final themed = theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: AppTheme.fontFamily));
      // real font so the width is honest
      final card = VisitingChefsCard(compact: true, result: _ok([_chef(1, CampusTime.wall(2026, 10, 14, 11), CampusTime.wall(2026, 10, 14, 14))]));
      await tester.pumpWidget(MaterialApp(theme: themed, home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 159, child: card)))));
      await tester.pumpAndSettle();
      final text = find.text('No more chefs');
      expect(text, findsOneWidget);
      expect(tester.getSize(text).height, lessThan(17 * 1.25 * 1.5));
    });
  });

  group('card', () {
    testWidgets('hero pill and rows count only listed chefs', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15));
      await _pump(tester, VisitingChefsCard(result: _ok([_chef(1, start, end), _chef(2, CampusTime.wall(2026, 10, 14, 16), CampusTime.wall(2026, 10, 14, 19)), _chef(3, null, null)])));
      expect(find.text('Chef 1'), findsNothing);
      expect(find.text('Chef 2'), findsOneWidget);
      expect(find.text('Chef 3'), findsOneWidget);
      expect(find.text('2 today'), findsOneWidget);
    });

    testWidgets('every chef ended says no more chefs and nothing else', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 22));
      await _pump(tester, VisitingChefsCard(result: _ok([_chef(1, start, end)])));
      expect(find.text('No more chefs today'), findsOneWidget);
      expect(find.text('Menus unavailable'), findsNothing);
      expect(find.text('No visiting chefs today'), findsNothing);
      expect(find.text('View on RIT'), findsNothing);
      expect(find.textContaining('today'), findsOneWidget);
    });

    testWidgets('an unavailable fetch still says unavailable', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 22));
      await _pump(tester, VisitingChefsCard(result: Result(value: ChefCollection(data: const [], stale: false, availability: Availability.unavailable), state: DataState.ok)));
      expect(find.text('Menus unavailable'), findsOneWidget);
      expect(find.text('No more chefs today'), findsNothing);
    });

    testWidgets('a real quiet day keeps its own title', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 22));
      await _pump(tester, VisitingChefsCard(result: _ok(const [])));
      expect(find.text('No visiting chefs today'), findsOneWidget);
    });

    testWidgets('the all-chefs sheet lists only listed chefs', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15));
      await _pump(tester, VisitingChefsCard(compact: true, result: _ok([_chef(1, start, end), _chef(2, CampusTime.wall(2026, 10, 14, 16), CampusTime.wall(2026, 10, 14, 19))])));
      await tester.tap(find.text('1 today'));
      await tester.pumpAndSettle();
      expect(find.text('1 visiting chef today'), findsOneWidget);
      expect(find.text('Chef 1'), findsNothing);
      expect(find.text('Chef 2'), findsOneWidget);
    });
  });
}
