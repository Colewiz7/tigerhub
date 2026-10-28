/// Compact Today cards on a phone: a label, one short value, a quiet caption.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dashboard_campus_cards.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/compact_card.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

// wed oct 14 2026
final _today = DateTime(2026, 10, 14);

RecreationFacility _facility(String name, List<(String, String)> today, [List<(String, String)> tomorrow = const []]) => RecreationFacility(
  name: name,
  days: [
    RecreationDay(serviceDate: _today, closed: false, spans: [for (final (o, c) in today) RecreationSpan(opensAt: o, closesAt: c)]),
    RecreationDay(serviceDate: DateTime(2026, 10, 15), closed: false, spans: [for (final (o, c) in tomorrow) RecreationSpan(opensAt: o, closesAt: c)]),
  ],
);

final _pool = _facility('Judson/Hale Aquatics Center', [('14:30', '16:30'), ('19:00', '22:00')], [('06:00', '09:00')]);

DateTime _wall(int hour, [int minute = 0]) => DateTime(2026, 10, 14, hour, minute);

Future<void> _pump(WidgetTester tester, Widget card, {double scale = 1, double width = 390}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.topLeft, child: card))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // real rubik, ahem would measure every glyph square
  setUpAll(loadGoldenFonts);
  setUp(() => RitClock.pin(DateTime.utc(2026, 10, 14, 16)));
  tearDown(RitClock.reset);

  group('visiting chefs', () {
    test('counts today, says none, or says unavailable', () {
      expect(chefsCompactValue(_ok([const MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A')])), '1 today');
      expect(chefsCompactValue(_ok<MenuItem>(const [])), 'None today');
      expect(chefsCompactValue(Result(value: ChefCollection(data: const [], stale: false, availability: Availability.unavailable), state: DataState.ok)), 'Unavailable');
      expect(chefsCompactValue(const Result(value: null, state: DataState.priming)), isNull);
    });

    testWidgets('a compact chefs card on a phone has a value and no list', (tester) async {
      await _pump(tester, VisitingChefsCard(compact: true, result: _ok(const [MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A'), MenuItem(id: 2, locationName: 'Gracies', name: 'Chef B')])));
      expect(find.byType(CompactCard), findsOneWidget);
      expect(find.text('2 today'), findsOneWidget);
      expect(find.text('Visiting chefs'), findsOneWidget);
      expect(find.byType(StatusRow), findsNothing);
    });

    testWidgets('tapping anywhere on it shows every chef', (tester) async {
      await _pump(tester, VisitingChefsCard(compact: true, result: _ok(const [MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A')])));
      await tester.tap(find.text('1 today'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('facility', () {
    test('short names, and the first word for one not in the list', () {
      expect(facilityShortName('Judson/Hale Aquatics Center'), 'Pool');
      expect(facilityShortName('Wiedman Fitness Center'), 'Gym');
      expect(facilityShortName('Polisseni Center'), 'Polisseni');
    });

    test('a new facility card starts on the pool', () {
      expect(defaultFacilityName([_facility('Wiedman Fitness Center', const []), _pool]), 'Judson/Hale Aquatics Center');
      expect(defaultFacilityName([_facility('Wiedman Fitness Center', const [])]), 'Wiedman Fitness Center');
      expect(defaultFacilityName(const []), isNull);
    });

    test('before, during, between and after the sessions', () {
      expect(facilityCompact(_pool, _wall(13)).value, 'Opens 2:30 PM');
      expect(facilityCompact(_pool, _wall(15)).value, 'Until 4:30 PM');
      expect(facilityCompact(_pool, _wall(17)).value, 'Opens 7 PM');
      expect(facilityCompact(_pool, _wall(20)).value, 'Until 10 PM');
      final after = facilityCompact(_pool, _wall(22, 30));
      expect(after.value, 'Closed today');
      expect(after.caption, 'Opens 6 AM tomorrow');
    });

    test('closed all day with nothing tomorrow has no caption', () {
      final shut = _facility('Turf Field', const []);
      expect(facilityCompact(shut, _wall(10)), (value: 'Closed today', caption: null, quiet: true));
    });

    test('no hours published says nothing', () {
      final none = RecreationFacility(name: 'Turf Field', days: const []);
      expect(facilityCompact(none, _wall(10)).value, isNull);
    });

    testWidgets('a compact facility card with no pick shows the pool', (tester) async {
      await _pump(tester, FacilityHoursCard(compact: true, result: _ok([_facility('Wiedman Fitness Center', [('10:00', '23:00')]), _pool])));
      expect(find.text('Pool'), findsOneWidget);
      // noon on campus, the pool opens at 2:30
      expect(find.text('Opens 2:30 PM'), findsOneWidget);
    });
  });

  testWidgets('from 600 wide a compact card keeps its old look', (tester) async {
    await _pump(tester, VisitingChefsCard(compact: true, result: _ok(const [MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A')])), width: 700);
    expect(find.byType(CompactCard), findsNothing);
  });

  // half of a 360 phone less margins and gap, less card padding
  const narrowest = (360 - 32 - 10) / 2 - 32;
  const values = ['5 today', '12 today', 'None today', 'Unavailable', 'Opens 7 PM', 'Until 11 PM', 'Closed today', 'Opens 2:30 PM', 'Until 4:30 PM'];

  for (final scale in [1.0, 1.35]) {
    testWidgets('every value fits the narrowest half card at ${scale}x, never cut', (tester) async {
      await _pump(tester, const SizedBox(), scale: scale);
      final context = tester.element(find.byType(SizedBox).last);
      final style = CompactCard.valueStyle(context)!.copyWith(fontFamily: AppTheme.fontFamily);
      for (final value in values) {
        final painter = TextPainter(text: TextSpan(text: value, style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.linear(scale))..layout(maxWidth: narrowest);
        // one line at 1x, two at most when text is turned up
        final lines = painter.computeLineMetrics().length;
        final limit = scale > 1 ? 2 : 1;
        expect(lines, lessThanOrEqualTo(limit), reason: '"$value" at ${scale}x took $lines lines');
        painter.dispose();
      }
    });
  }
}
