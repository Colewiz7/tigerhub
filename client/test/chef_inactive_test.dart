/// A chef who is not on right now reads quieter than one who is.
///
/// Runs under the CI TZ matrix. Every instant is absolute, so the answer must
/// not move with the device zone.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/chef_listing.dart';
import 'package:tigerhub/data/chef_location_color.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'golden_harness.dart';

MenuItem _chef(int id, DateTime? start, DateTime? end, {String place = 'RITZ'}) =>
    MenuItem(id: id, name: 'Chef $id', locationName: place, startsAt: start, endsAt: end);

Result<Collection<MenuItem>> _ok(List<MenuItem> data) => Result(value: ChefCollection(data: data, stale: false), state: DataState.ok);

double _contrast(Color a, Color b) {
  final hi = math.max(a.computeLuminance(), b.computeLuminance());
  final lo = math.min(a.computeLuminance(), b.computeLuminance());
  return (hi + 0.05) / (lo + 0.05);
}

ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness);

List<Color> _surfaces(ColorScheme s) => [
  s.surface,
  s.surfaceContainerLowest,
  s.surfaceContainerLow,
  s.surfaceContainer,
  s.surfaceContainerHigh,
  s.surfaceContainerHighest,
];

double _hue(Color c) => HSLColor.fromColor(c).hue;

Future<void> _pump(WidgetTester tester, Widget card, {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.from(_scheme(brightness)), home: Scaffold(body: SingleChildScrollView(child: card))),
  );
  await tester.pumpAndSettle();
}

Color? _colorOf(WidgetTester tester, String text) {
  final style = tester.widget<Text>(find.text(text)).style;
  return style?.color;
}

String _label(WidgetTester tester, String name) => tester.getSemantics(find.text(name)).label;

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(RitClock.reset);

  final start = CampusTime.wall(2026, 10, 14, 16);
  final end = CampusTime.wall(2026, 10, 14, 18);
  const second = Duration(seconds: 1);

  group('chefPhase', () {
    final chef = _chef(1, start, end);

    test('before the start is upcoming', () {
      expect(chefPhase(chef, now: start.subtract(const Duration(hours: 3))), ChefPhase.upcoming);
      expect(chefPhase(chef, now: start.subtract(second)), ChefPhase.upcoming);
    });

    test('the start minute is active', () {
      expect(chefPhase(chef, now: start), ChefPhase.active);
      expect(chefPhase(chef, now: start.add(second)), ChefPhase.active);
    });

    test('the last second before the end is active, the end minute is ended', () {
      expect(chefPhase(chef, now: end.subtract(second)), ChefPhase.active);
      expect(chefPhase(chef, now: end), ChefPhase.ended);
    });

    test('ended holds through the grace window', () {
      expect(chefPhase(chef, now: end.add(const Duration(minutes: 29, seconds: 59))), ChefPhase.ended);
      expect(chefStillListed(chef, now: end.add(const Duration(minutes: 29, seconds: 59))), isTrue);
    });

    test('no time is untimed', () {
      expect(chefPhase(_chef(2, null, null), now: start), ChefPhase.untimed);
      expect(ChefPhase.untimed.inactive, isFalse);
    });

    test('only active and untimed stay full strength', () {
      expect({for (final p in ChefPhase.values) p: p.inactive}, {
        ChefPhase.untimed: false,
        ChefPhase.active: false,
        ChefPhase.upcoming: true,
        ChefPhase.ended: true,
      });
    });

    test('a start with no end is upcoming, then active all day', () {
      final open = _chef(3, start, null);
      expect(chefPhase(open, now: start.subtract(second)), ChefPhase.upcoming);
      expect(chefPhase(open, now: start), ChefPhase.active);
      expect(chefPhase(open, now: CampusTime.wall(2026, 10, 14, 23, 59)), ChefPhase.active);
    });

    test('an end with no start is active until it ends', () {
      final until = _chef(4, null, end);
      expect(chefPhase(until, now: end.subtract(second)), ChefPhase.active);
      expect(chefPhase(until, now: end), ChefPhase.ended);
    });

    test('an overnight slot is active across midnight', () {
      final late = _chef(5, CampusTime.wall(2026, 10, 14, 22), CampusTime.wall(2026, 10, 15, 1));
      expect(chefPhase(late, now: CampusTime.wall(2026, 10, 14, 21, 59)), ChefPhase.upcoming);
      expect(chefPhase(late, now: CampusTime.wall(2026, 10, 15, 0, 30)), ChefPhase.active);
      expect(chefPhase(late, now: CampusTime.wall(2026, 10, 15, 1)), ChefPhase.ended);
      // an end stamped on the start's date still reads as next day
      final sameDay = _chef(6, CampusTime.wall(2026, 10, 14, 22), CampusTime.wall(2026, 10, 14, 1));
      expect(chefPhase(sameDay, now: CampusTime.wall(2026, 10, 15, 0, 30)), ChefPhase.active);
    });

    test('uses the pinned clock by default', () {
      RitClock.pin(start.subtract(const Duration(minutes: 1)));
      expect(chefPhase(chef), ChefPhase.upcoming);
      RitClock.pin(start);
      expect(chefPhase(chef), ChefPhase.active);
    });

    // 16:00 to 18:00 on campus is 20:00Z to 22:00Z while daylight time holds
    test('the same slot written in each of four zones gives the same phase', () {
      final stamps = [
        ('2026-10-14T16:00:00-04:00', '2026-10-14T18:00:00-04:00'),
        ('2026-10-14T13:00:00-07:00', '2026-10-14T15:00:00-07:00'),
        ('2026-10-15T05:00:00+09:00', '2026-10-15T07:00:00+09:00'),
        ('2026-10-14T20:00:00Z', '2026-10-14T22:00:00Z'),
      ];
      for (final (from, to) in stamps) {
        final c = _chef(1, DateTime.parse(from), DateTime.parse(to));
        expect(chefPhase(c, now: DateTime.utc(2026, 10, 14, 19, 59, 59)), ChefPhase.upcoming, reason: from);
        expect(chefPhase(c, now: DateTime.utc(2026, 10, 14, 20)), ChefPhase.active, reason: from);
        expect(chefPhase(c, now: DateTime.utc(2026, 10, 14, 21, 59, 59)), ChefPhase.active, reason: from);
        expect(chefPhase(c, now: DateTime.utc(2026, 10, 14, 22)), ChefPhase.ended, reason: from);
      }
    });

    test('the phase does not move across the fall back', () {
      // 00:30 to 01:45 EDT on 1 Nov, the clock falls back at 06:00Z
      final c = _chef(1, DateTime.utc(2026, 11, 1, 4, 30), DateTime.utc(2026, 11, 1, 5, 45));
      expect(chefPhase(c, now: DateTime.utc(2026, 11, 1, 4, 29)), ChefPhase.upcoming);
      expect(chefPhase(c, now: DateTime.utc(2026, 11, 1, 5, 44)), ChefPhase.active);
      expect(chefPhase(c, now: DateTime.utc(2026, 11, 1, 5, 45)), ChefPhase.ended);
    });
  });

  group('nextChefChange', () {
    test('is the soonest start, end or cutoff still ahead', () {
      final chefs = [_chef(1, start, end)];
      expect(nextChefChange(chefs, now: start.subtract(const Duration(hours: 1))), start);
      expect(nextChefChange(chefs, now: start), end);
      expect(nextChefChange(chefs, now: end), end.add(chefGrace));
      expect(nextChefChange(chefs, now: end.add(chefGrace)), isNull);
    });

    test('takes the earliest across chefs and ignores untimed ones', () {
      final chefs = [_chef(1, start, end), _chef(2, CampusTime.wall(2026, 10, 14, 14), CampusTime.wall(2026, 10, 14, 15)), _chef(3, null, null)];
      expect(nextChefChange(chefs, now: CampusTime.wall(2026, 10, 14, 13)), CampusTime.wall(2026, 10, 14, 14));
      expect(nextChefChange([_chef(3, null, null)]), isNull);
    });
  });

  for (final brightness in Brightness.values) {
    group('contrast, ${brightness.name}', () {
      final scheme = _scheme(brightness);

      test('every muted location colour is at least 4.5:1 on every card surface', () {
        for (final entry in chefLocationColors.entries) {
          final chef = MenuItem(id: 1, name: 'Chef', locationName: entry.value.name, locationId: entry.key);
          final muted = chefLocationColor(chef, scheme, muted: true);
          for (final surface in _surfaces(scheme)) {
            expect(_contrast(muted, surface), greaterThanOrEqualTo(4.5), reason: '${entry.value.name} on $surface');
          }
        }
      });

      test('a muted location colour keeps its hue and is softer than the full one', () {
        for (final entry in chefLocationColors.entries) {
          final chef = MenuItem(id: 1, name: 'Chef', locationName: entry.value.name, locationId: entry.key);
          final full = chefLocationColor(chef, scheme);
          final muted = chefLocationColor(chef, scheme, muted: true);
          expect(muted, isNot(full), reason: entry.value.name);
          var drift = (_hue(full) - _hue(muted)).abs();
          if (drift > 180) drift = 360 - drift;
          expect(drift, lessThan(30), reason: entry.value.name);
          expect(HSLColor.fromColor(muted).saturation, lessThan(HSLColor.fromColor(full).saturation), reason: entry.value.name);
        }
      });

      test('the muted title colour and the fallback are at least 4.5:1 on every surface', () {
        final unknown = MenuItem(id: 1, name: 'Chef', locationName: 'Elsewhere');
        expect(chefLocationColor(unknown, scheme, muted: true), scheme.onSurfaceVariant);
        for (final surface in _surfaces(scheme)) {
          expect(_contrast(scheme.onSurfaceVariant, surface), greaterThanOrEqualTo(4.5));
        }
      });
    });
  }

  group('card', () {
    final active = _chef(1, CampusTime.wall(2026, 10, 14, 11), CampusTime.wall(2026, 10, 14, 14));
    final upcoming = _chef(2, CampusTime.wall(2026, 10, 14, 16), CampusTime.wall(2026, 10, 14, 19));
    final ended = _chef(3, CampusTime.wall(2026, 10, 14, 8), CampusTime.wall(2026, 10, 14, 12));
    final untimed = _chef(4, null, null);
    final now = CampusTime.wall(2026, 10, 14, 12, 15);

    for (final brightness in Brightness.values) {
      testWidgets('inactive names are muted, active and untimed stay full, ${brightness.name}', (tester) async {
        RitClock.pin(now);
        final scheme = _scheme(brightness);
        await _pump(tester, VisitingChefsCard(result: _ok([active, upcoming, ended])), brightness: brightness);
        expect(_colorOf(tester, 'Chef 1'), AppTheme.from(scheme).textTheme.titleMedium?.color);
        expect(_colorOf(tester, 'Chef 2'), scheme.onSurfaceVariant);
        expect(_colorOf(tester, 'Chef 3'), scheme.onSurfaceVariant);
        expect(_colorOf(tester, 'Chef 1'), isNot(scheme.onSurfaceVariant));
      });

      testWidgets('a chef with no time stays full strength, ${brightness.name}', (tester) async {
        RitClock.pin(now);
        final scheme = _scheme(brightness);
        await _pump(tester, VisitingChefsCard(result: _ok([untimed])), brightness: brightness);
        expect(_colorOf(tester, 'Chef 4'), AppTheme.from(scheme).textTheme.titleMedium?.color);
        expect(tester.widget<Text>(find.text('RITZ')).style?.color, chefLocationColor(untimed, scheme));
      });
    }

    testWidgets('the location keeps a hue but softens when inactive', (tester) async {
      RitClock.pin(now);
      final scheme = _scheme(Brightness.light);
      await _pump(tester, VisitingChefsCard(result: _ok([active, upcoming])));
      final full = chefLocationColor(active, scheme);
      final muted = chefLocationColor(active, scheme, muted: true);
      final places = find.text('RITZ');
      expect(places, findsNWidgets(2));
      expect(tester.widget<Text>(places.at(0)).style?.color, full);
      expect(tester.widget<Text>(places.at(1)).style?.color, muted);
    });

    testWidgets('rows keep the same height whatever the phase', (tester) async {
      RitClock.pin(now);
      await _pump(tester, VisitingChefsCard(result: _ok([active, upcoming, ended])));
      double heightOf(String name) {
        final row = find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
        return tester.getSize(row).height;
      }

      final heights = {for (final n in ['Chef 1', 'Chef 2', 'Chef 3']) n: heightOf(n)};
      expect(heights.values.toSet().length, 1, reason: '$heights');
    });

    testWidgets('a screen reader hears when an inactive chef starts or has ended', (tester) async {
      RitClock.pin(now);
      final handle = tester.ensureSemantics();
      await _pump(tester, VisitingChefsCard(result: _ok([active, upcoming, ended])));
      expect(_label(tester, 'Chef 1'), startsWith('Chef 1, 11 AM to 2 PM, RITZ'));
      expect(_label(tester, 'Chef 1'), isNot(contains('starts')));
      expect(_label(tester, 'Chef 1'), isNot(contains('ended')));
      expect(_label(tester, 'Chef 2'), startsWith('Chef 2, 4 PM to 7 PM, RITZ, starts at 4 PM'));
      expect(_label(tester, 'Chef 3'), startsWith('Chef 3, 8 AM to noon, RITZ, ended'));
      handle.dispose();
    });

    testWidgets('the sheet dims the same way and says why', (tester) async {
      RitClock.pin(now);
      final handle = tester.ensureSemantics();
      final scheme = _scheme(Brightness.light);
      await _pump(tester, VisitingChefsCard(compact: true, result: _ok([active, upcoming, ended, untimed])));
      await tester.tap(find.text('4 today'));
      await tester.pumpAndSettle();
      expect(find.text('4 visiting chefs today'), findsOneWidget);
      expect(_colorOf(tester, 'Chef 1'), isNot(scheme.onSurfaceVariant));
      expect(_colorOf(tester, 'Chef 2'), scheme.onSurfaceVariant);
      expect(_colorOf(tester, 'Chef 3'), scheme.onSurfaceVariant);
      expect(_colorOf(tester, 'Chef 4'), isNot(scheme.onSurfaceVariant));
      expect(_label(tester, 'Chef 2'), contains('starts at 4 PM'));
      expect(_label(tester, 'Chef 3'), endsWith('ended'));
      expect(_label(tester, 'Chef 1'), isNot(contains('ended')));
      expect(_label(tester, 'Chef 4'), 'Chef 4, RITZ');
      handle.dispose();
    });

    testWidgets('the sheet re-evaluates when a slot starts', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15, 59, 30));
      final scheme = _scheme(Brightness.light);
      await _pump(tester, VisitingChefsCard(compact: true, result: _ok([upcoming])));
      await tester.tap(find.text('1 today'));
      await tester.pumpAndSettle();
      expect(_colorOf(tester, 'Chef 2'), scheme.onSurfaceVariant);
      RitClock.pin(CampusTime.wall(2026, 10, 14, 16));
      await tester.pump(const Duration(seconds: 30));
      expect(_colorOf(tester, 'Chef 2'), isNot(scheme.onSurfaceVariant));
    });
  });

  group('timer', () {
    final scheme = _scheme(Brightness.light);
    final chef = _chef(1, CampusTime.wall(2026, 10, 14, 16), CampusTime.wall(2026, 10, 14, 18));

    testWidgets('rearms at the next start, with no tick in between', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15, 30));
      await _pump(tester, VisitingChefsCard(result: _ok([chef])));
      expect(_colorOf(tester, 'Chef 1'), scheme.onSurfaceVariant);

      // the start is 30 minutes away: nothing fires before it
      await tester.pump(const Duration(minutes: 29));
      expect(_colorOf(tester, 'Chef 1'), scheme.onSurfaceVariant);

      RitClock.pin(CampusTime.wall(2026, 10, 14, 16));
      await tester.pump(const Duration(minutes: 1));
      expect(_colorOf(tester, 'Chef 1'), isNot(scheme.onSurfaceVariant));
    });

    testWidgets('then rearms at the end, then at the cutoff', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 15, 59));
      await _pump(tester, VisitingChefsCard(result: _ok([chef])));
      RitClock.pin(CampusTime.wall(2026, 10, 14, 16));
      await tester.pump(const Duration(minutes: 1));
      expect(_colorOf(tester, 'Chef 1'), isNot(scheme.onSurfaceVariant));

      RitClock.pin(CampusTime.wall(2026, 10, 14, 18));
      await tester.pump(const Duration(hours: 2));
      expect(_colorOf(tester, 'Chef 1'), scheme.onSurfaceVariant);

      RitClock.pin(CampusTime.wall(2026, 10, 14, 18, 30));
      await tester.pump(const Duration(minutes: 30));
      expect(find.text('Chef 1'), findsNothing);
    });

    testWidgets('a start already past arms nothing for it', (tester) async {
      RitClock.pin(CampusTime.wall(2026, 10, 14, 17));
      expect(nextChefChange([chef]), CampusTime.wall(2026, 10, 14, 18));
      await _pump(tester, VisitingChefsCard(result: _ok([chef])));
      expect(_colorOf(tester, 'Chef 1'), isNot(scheme.onSurfaceVariant));
    });
  });
}
