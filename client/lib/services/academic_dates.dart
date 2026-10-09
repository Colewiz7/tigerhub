/// High-value dates from RIT's official Rochester academic calendar.
///
/// This deliberately stores deadlines and schedule changes, not every
/// administrative date. Past entries are filtered at read time so an old app
/// build cannot present an expired deadline as upcoming.
library;

import '../data/campus_time.dart';

class AcademicMilestone {
  const AcademicMilestone(this.date, this.title, this.detail);

  final DateTime date;
  final String title;
  final String detail;
}

final List<AcademicMilestone> academicMilestones = [
  AcademicMilestone(
    DateTime(2026, 8, 31),
    'Add/drop ends',
    'Last day of the fall add/drop period',
  ),
  AcademicMilestone(DateTime(2026, 9, 7), 'Labor Day', 'University closed'),
  AcademicMilestone(
    DateTime(2026, 10, 12),
    'Fall break begins',
    'No classes October 12–13',
  ),
  AcademicMilestone(
    DateTime(2026, 11, 6),
    'Withdrawal deadline',
    'Last day to drop with a W',
  ),
  AcademicMilestone(
    DateTime(2026, 11, 25),
    'Thanksgiving break begins',
    'No classes; university closes at 2 p.m.',
  ),
  AcademicMilestone(
    DateTime(2026, 12, 7),
    'Last day of fall classes',
    'Fall graduation application deadline',
  ),
  AcademicMilestone(
    DateTime(2026, 12, 8),
    'Reading day',
    'Final exams begin December 9',
  ),
  AcademicMilestone(
    DateTime(2027, 1, 11),
    'Spring classes begin',
    'First day of spring add/drop',
  ),
  AcademicMilestone(
    DateTime(2027, 1, 19),
    'Add/drop ends',
    'Last day of the spring add/drop period',
  ),
  AcademicMilestone(
    DateTime(2027, 3, 7),
    'Spring break begins',
    'No classes March 7–14',
  ),
  AcademicMilestone(
    DateTime(2027, 4, 2),
    'Withdrawal deadline',
    'Last day to drop with a W',
  ),
  AcademicMilestone(
    DateTime(2027, 4, 26),
    'Last day of spring classes',
    'Spring graduation application deadline',
  ),
  AcademicMilestone(
    DateTime(2027, 4, 27),
    'Reading day',
    'Final exams begin April 28',
  ),
  AcademicMilestone(
    DateTime(2027, 5, 7),
    'Commencement begins',
    'Ceremonies May 7–8',
  ),
];

List<AcademicMilestone> upcomingAcademicMilestones({
  DateTime? now,
  int? limit,
}) {
  // [now] is campus wall clock fields; the default is the campus day.
  final clock = now ?? CampusTime.wallNow();
  final today = DateTime(clock.year, clock.month, clock.day);
  final upcoming = academicMilestones
      .where((item) => !item.date.isBefore(today))
      .toList();
  return limit == null || upcoming.length <= limit
      ? upcoming
      : upcoming.take(limit).toList();
}
