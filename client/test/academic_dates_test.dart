import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/academic_dates_card.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/services/academic_dates.dart';
import 'package:tigerhub/theme/app_theme.dart';

void main() {
  test('past deadlines disappear but today remains actionable', () {
    final dates = upcomingAcademicMilestones(now: DateTime(2026, 9, 7));

    expect(dates.first.title, 'Labor Day');
    expect(dates.any((date) => date.date == DateTime(2026, 8, 31)), isFalse);
  });

  test('the caller can request only the next few milestones', () {
    final dates = upcomingAcademicMilestones(
      now: DateTime(2026, 8, 30),
      limit: 3,
    );
    expect(dates, hasLength(3));
    expect(dates.first.title, 'Add/drop ends');
  });

  tearDown(RitClock.reset);

  test('the default day is the campus day, not the device day', () {
    // 02:00 UTC on 1 Sep is still the evening of 31 Aug in Rochester.
    RitClock.pin(DateTime.utc(2026, 9, 1, 2));
    final dates = upcomingAcademicMilestones(limit: 1);
    expect(dates.first.title, 'Add/drop ends');
  });

  testWidgets('dashboard card shows the next deadline and countdown', (
    tester,
  ) async {
    RitClock.pin(CampusTime.wall(2026, 8, 31, 12));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: const Scaffold(
          body: SizedBox(width: 520, height: 620, child: AcademicDatesCard()),
        ),
      ),
    );

    expect(find.text('Academic Dates'), findsOneWidget);
    expect(find.text('Add/drop ends'), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
  });
}
