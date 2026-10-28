/// High-value dates from RIT's official Rochester academic calendar.
///
/// This deliberately stores deadlines and schedule changes, not every
/// administrative date. Past entries are filtered at read time so an old app
/// build cannot present an expired deadline as upcoming.
library;

import 'package:intl/intl.dart';

import '../data/campus_time.dart';

class AcademicMilestone {
  const AcademicMilestone(this.date, this.title, this.detail, {this.end});

  final DateTime date;
  final String title;
  final String detail;

  /// Last day of a multi-day entry, or null for a single day.
  final DateTime? end;

  /// The last day this entry is still current.
  DateTime get lastDay => end ?? date;

  /// "Nov 26–27" or "Dec 19–Jan 10" for a range, [single] for one day.
  String dateText(DateFormat single) {
    final last = end;
    if (last == null) return single.format(date);
    final month = DateFormat('MMM');
    final day = DateFormat('d');
    final tail = last.month == date.month
        ? day.format(last)
        : '${month.format(last)} ${day.format(last)}';
    return '${month.format(date)} ${day.format(date)}–$tail';
  }
}

final List<AcademicMilestone> academicMilestones = [
  AcademicMilestone(
    DateTime(2026, 8, 31),
    'Add/drop ends',
    'Last day to add or drop',
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
    'RIT closes at 2 p.m.',
  ),
  AcademicMilestone(
    DateTime(2026, 11, 26),
    'Thanksgiving holiday',
    'Classes resume Nov 30',
    end: DateTime(2026, 11, 27),
  ),
  AcademicMilestone(
    DateTime(2026, 12, 7),
    'Last day of fall classes',
    'Graduation applications due',
  ),
  AcademicMilestone(
    DateTime(2026, 12, 8),
    'Reading day',
    'Final exams begin December 9',
  ),
  AcademicMilestone(
    DateTime(2026, 12, 19),
    'Fall to spring break',
    'Between semesters',
    end: DateTime(2027, 1, 10),
  ),
  AcademicMilestone(
    DateTime(2026, 12, 25),
    'Employee holidays',
    'RIT designated holidays',
    end: DateTime(2027, 1, 1),
  ),
  AcademicMilestone(
    DateTime(2027, 1, 11),
    'Spring classes begin',
    'First day of spring add/drop',
  ),
  AcademicMilestone(
    DateTime(2027, 1, 19),
    'Add/drop ends',
    'Last day to add or drop',
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
    'Graduation applications due',
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
  AcademicMilestone(
    DateTime(2027, 5, 9),
    'Spring to summer break',
    'Between semester and term',
    end: DateTime(2027, 5, 11),
  ),
  AcademicMilestone(
    DateTime(2027, 8, 13),
    'Summer to fall break',
    'Between term and semester',
    end: DateTime(2027, 8, 22),
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
      .where((item) => !item.lastDay.isBefore(today))
      .toList();
  return limit == null || upcoming.length <= limit
      ? upcoming
      : upcoming.take(limit).toList();
}
