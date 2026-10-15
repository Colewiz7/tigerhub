/// One event, as a container row.
///
/// Past and future are visually distinct: a finished event dims and is marked,
/// so the eye can separate "already happened" from "still to come" without
/// reading any times.
library;

import 'package:flutter/material.dart';

import '../data/campus_time.dart';
import '../models/api_models.dart';
import '../theme/semantic.dart';
import '../widgets/event_details_sheet.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';

IconData iconForEventType(String? type) {
  final t = (type ?? '').toLowerCase();
  if (t.contains('athletics')) return Icons.sports_score_rounded;
  if (t.contains('meeting')) return Icons.groups_rounded;
  if (t.contains('workshop') || t.contains('training')) {
    return Icons.construction_rounded;
  }
  if (t.contains('religious') || t.contains('spiritual')) {
    return Icons.self_improvement_rounded;
  }
  if (t.contains('recreation') || t.contains('sport')) {
    return Icons.sports_basketball_rounded;
  }
  if (t.contains('blood')) return Icons.bloodtype_rounded;
  if (t.contains('tabling') || t.contains('outreach')) {
    return Icons.campaign_rounded;
  }
  return Icons.event_rounded;
}

class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.event,
    this.now,
    this.boosted = false,
    this.forceDimmed = false,
    this.dense = false,
  });

  final CampusEvent event;

  /// The dashboard's condensed phone row.
  final bool dense;

  /// Matched a boost keyword. Gets a subtle accent marker.
  final bool boosted;

  /// Rendered as part of an expanded hidden list.
  final bool forceDimmed;

  /// Injectable so the past/future split is testable.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final semantic = Semantic.of(context);
    final text = Theme.of(context).textTheme;
    final moment = now ?? CampusTime.nowUtc();

    // An event is past once its end has gone by, or its start if it has no end.
    final ends = event.endsAt ?? event.startsAt;
    final isPast = ends.isBefore(moment) || forceDimmed;

    final when = event.allDay ? 'All day' : formatDayAndClock(event.startsAt);

    // Show the day whenever the event is not today. Two genuinely different
    // events on different days used to render as an identical clock time,
    // which read as a duplicated row.
    final sameDay =
        CampusTime.dateOf(event.startsAt) == CampusTime.dateOf(moment);
    final stamp = event.allDay
        ? 'ALL DAY'
        : (sameDay
              ? formatClock(event.startsAt)
              : formatDayAndClock(event.startsAt));

    // The dashboard row says the time once, in the status line, with the place
    // after a middle dot ("Fri 5:00 PM · SAU"), and keeps the trailing slot
    // for "ENDED". The standard row keeps the time on the right.
    final place = event.location?.isNotEmpty == true ? event.location! : null;
    final denseWhen = event.allDay ? 'All day' : stamp;
    final denseSubtitle = place == null ? denseWhen : '$denseWhen · $place';
    final ended = Text(
      'ENDED',
      style: text.labelSmall?.copyWith(color: semantic.closed),
    );

    return StatusRow(
      dense: dense,
      icon: forceDimmed
          ? Icons.visibility_off_rounded
          : (isPast
                ? Icons.history_rounded
                : iconForEventType(event.eventType)),
      title: boosted ? '✦ ${event.title}' : event.title,
      subtitle: dense ? denseSubtitle : (place ?? when),
      accent: boosted
          ? Theme.of(context).colorScheme.primary
          : (isPast ? semantic.closed : semantic.open),
      emphasis: isPast ? RowEmphasis.dimmed : RowEmphasis.normal,
      semanticHint: 'Opens event details',
      onTap: () => showEventDetailsSheet(context, event),
      trailing: dense
          ? (isPast ? ended : null)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stamp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: isPast
                        ? semantic.closed
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (isPast) ended,
              ],
            ),
    );
  }
}
