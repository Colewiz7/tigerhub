import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/academic_dates.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/empty_state.dart';
import '../widgets/glyph.dart';
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
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final daysAway = dates.isEmpty
        ? null
        : dates.first.date.difference(day).inDays;

    return CardShell(
      glyph: GlyphKind.events,
      title: 'Academic Dates',
      dragHandle: dragHandle,
      hero: daysAway == null
          ? null
          : ScallopedBadge(
              value: daysAway == 0 ? 'NOW' : '$daysAway',
              label: daysAway == 0
                  ? 'TODAY'
                  : (daysAway == 1 ? 'DAY TO GO' : 'DAYS TO GO'),
              size: 88,
            ),
      child: dates.isEmpty
          ? const EmptyState(
              kind: EmptyKind.noEvents,
              title: 'No more dates in this academic year',
            )
          : BoundedList(
              itemCount: dates.length,
              itemHeight: StatusRow.heightFor(context),
              noun: 'dates',
              onShowAll: onShowAll,
              itemBuilder: (context, index) => StatusRow(
                icon: index == 0
                    ? Icons.upcoming_rounded
                    : Icons.calendar_today_rounded,
                title: dates[index].title,
                subtitle: dates[index].detail,
                trailing: Text(
                  formatter.format(dates[index].date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
    );
  }
}
