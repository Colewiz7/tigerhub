import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/academic_dates_card.dart';
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

  testWidgets('dashboard card shows the next deadline and countdown', (
    tester,
  ) async {
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
