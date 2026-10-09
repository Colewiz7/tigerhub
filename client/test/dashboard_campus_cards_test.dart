import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dashboard_campus_cards.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

void main() {
  setUp(() => RitClock.pin(DateTime.utc(2026, 8, 30, 16)));
  tearDown(RitClock.reset);

  testWidgets('facility card honors its saved facility scope', (tester) async {
    final facilities = [
      RecreationFacility(
        name: 'Aquatics Center',
        days: [
          RecreationDay(
            serviceDate: DateTime(2026, 8, 30),
            closed: false,
            spans: const [RecreationSpan(opensAt: '08:00', closesAt: '20:00')],
          ),
        ],
      ),
      const RecreationFacility(name: 'Turf Field', days: []),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 560,
            child: FacilityHoursCard(
              facilityName: 'Aquatics Center',
              result: Result(
                value: Collection(data: facilities, stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Aquatics Center'), findsWidgets);
    expect(find.text('8:00 AM to 8:00 PM'), findsOneWidget);
    expect(find.text('Turf Field'), findsNothing);
  });

  testWidgets('a dropped today shows hours unavailable, not tomorrow', (
    tester,
  ) async {
    final facility = RecreationFacility(
      name: 'Aquatics Center',
      droppedNested: 1,
      days: [
        RecreationDay(
          serviceDate: DateTime(2026, 8, 31),
          closed: false,
          spans: const [RecreationSpan(opensAt: '09:00', closesAt: '21:00')],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 560,
            child: FacilityHoursCard(
              result: Result(
                value: Collection(data: [facility], stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Hours unavailable'), findsOneWidget);
    expect(find.text('9:00 AM to 9:00 PM'), findsNothing);
  });
}
