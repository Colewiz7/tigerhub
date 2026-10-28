import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/campus_time.dart';
import '../services/academic_dates.dart';
import '../widgets/app_icon.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/context_actions.dart';
import '../widgets/empty_state.dart';
import '../widgets/scalloped_badge.dart';
import '../widgets/status_row.dart';

class AcademicDatesCard extends StatelessWidget {
  const AcademicDatesCard({super.key, this.dragHandle, this.onShowAll});

  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final dates = upcomingAcademicMilestones();
    final formatter = DateFormat('MMM d');
    final today = CampusTime.wallDate();
    // Whole calendar days, counted in UTC so a device DST change cannot make a
    // 23 or 25 hour day round the count down by one.
    // A range already under way counts as today.
    final daysAway = dates.isEmpty
        ? null
        : math.max(
            0,
            DateTime.utc(
              dates.first.date.year,
              dates.first.date.month,
              dates.first.date.day,
            ).difference(DateTime.utc(today.year, today.month, today.day)).inDays,
          );

    return CardShell(
      glyph: AppIconKind.events,
      title: 'Academic Dates',
      dragHandle: dragHandle,
      hero: daysAway == null
          ? null
          : CardHero(
              value: daysAway == 0 ? 'Now' : '$daysAway',
              label: daysAway == 0
                  ? 'Today'
                  : (daysAway == 1 ? 'Day to go' : 'Days to go'),
              pill: daysAway == 0
                  ? 'today'
                  : (daysAway == 1 ? '1 day to go' : '$daysAway days to go'),
            ),
      child: dates.isEmpty
          ? const EmptyState(
              kind: EmptyKind.noEvents,
              title: 'No more dates',
            )
          : BoundedList(
              itemCount: dates.length,
              itemHeight: StatusRow.heightFor(context, dense: true),
              dense: true,
              maxRows: phoneRowCap(context),
              noun: 'dates',
              onShowAll: onShowAll,
              itemBuilder: (context, index) => StatusRow(
                dense: true,
                icon: index == 0
                    ? AppIconKind.upcoming
                    : AppIconKind.day,
                title: dates[index].title,
                subtitle: dates[index].detail,
                actions: [
                  MenuAction.copy('${dates[index].title}\n${dates[index].dateText(formatter)}\n${dates[index].detail}'),
                ],
                trailing: Text(
                  dates[index].dateText(formatter),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
    );
  }
}
