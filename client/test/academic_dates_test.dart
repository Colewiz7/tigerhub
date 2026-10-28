import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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

  // dates and wording from rit.edu/calendar, 2026-2027
  const breaks = [
    (title: 'Thanksgiving holiday', detail: 'Classes resume Nov 30', start: (2026, 11, 26), end: (2026, 11, 27), text: 'Nov 26–27'),
    (title: 'Fall to spring break', detail: 'Between semesters', start: (2026, 12, 19), end: (2027, 1, 10), text: 'Dec 19–Jan 10'),
    (title: 'Employee holidays', detail: 'RIT designated holidays', start: (2026, 12, 25), end: (2027, 1, 1), text: 'Dec 25–Jan 1'),
    (title: 'Spring to summer break', detail: 'Between semester and term', start: (2027, 5, 9), end: (2027, 5, 11), text: 'May 9–11'),
    (title: 'Summer to fall break', detail: 'Between term and semester', start: (2027, 8, 13), end: (2027, 8, 22), text: 'Aug 13–22'),
  ];

  for (final item in breaks) {
    test('${item.title} is listed with its exact dates', () {
      final match = academicMilestones.where((m) => m.title == item.title);
      expect(match, hasLength(1));
      expect(match.single.date, DateTime(item.start.$1, item.start.$2, item.start.$3));
      expect(match.single.end, DateTime(item.end.$1, item.end.$2, item.end.$3));
      expect(match.single.detail, item.detail);
      expect(match.single.dateText(DateFormat('MMM d')), item.text);
    });
  }

  test('the milestones stay in date order', () {
    for (var i = 1; i < academicMilestones.length; i++) {
      expect(academicMilestones[i].date.isBefore(academicMilestones[i - 1].date), isFalse, reason: academicMilestones[i].title);
    }
  });

  test('a range stays listed through its last day and then drops', () {
    final during = upcomingAcademicMilestones(now: DateTime(2027, 1, 5));
    expect(during.first.title, 'Fall to spring break');
    expect(during.any((m) => m.title == 'Employee holidays'), isFalse);
    final lastDay = upcomingAcademicMilestones(now: DateTime(2027, 1, 10));
    expect(lastDay.first.title, 'Fall to spring break');
    final after = upcomingAcademicMilestones(now: DateTime(2027, 1, 11));
    expect(after.first.title, 'Spring classes begin');
  });

  testWidgets('dashboard card shows a break as a range and counts it as today', (tester) async {
    RitClock.pin(CampusTime.wall(2026, 12, 20, 12));
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

    expect(find.text('Fall to spring break'), findsOneWidget);
    expect(find.text('Dec 19–Jan 10'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
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
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });
}
