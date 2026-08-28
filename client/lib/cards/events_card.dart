/// Events card.
///
/// One merged feed from both sources, grouped by organizer. The backend joins
/// the CampusGroups club acronym to the Drupal club record, so `organizer`
/// already carries a real name rather than an acronym.
///
/// Grouping matters: FoodShare alone is 213 of 921 events, so an ungrouped
/// list reads as one club's feed.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';

class EventsCard extends StatelessWidget {
  const EventsCard({super.key, required this.result, this.dragHandle});

  final Result<Collection<CampusEvent>> result;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final events = result.value?.data ?? const <CampusEvent>[];

    return CardShell(
      title: 'Events',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      child: switch ((result.isPriming, events.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading events'),
        (_, true) => const EmptyNote(text: 'No upcoming events cached yet.'),
        _ => _Grouped(events: events),
      },
    );
  }
}

class _Grouped extends StatelessWidget {
  const _Grouped({required this.events});

  final List<CampusEvent> events;

  static const int _maxGroups = 6;
  static const int _maxPerGroup = 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final groups = <String, List<CampusEvent>>{};
    for (final event in events) {
      groups.putIfAbsent(event.organizer ?? 'Other', () => []).add(event);
    }

    // Busiest organizers first, so the feed leads with what is actually on.
    final ordered = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final shown = ordered.take(_maxGroups).toList();
    final hidden = ordered.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          RuledRow(
            last: i == shown.length - 1 && hidden <= 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shown[i].key.toUpperCase(),
                        style: text.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('${shown[i].value.length}', style: text.labelSmall),
                  ],
                ),
                const SizedBox(height: 4),
                for (final event in shown[i].value.take(_maxPerGroup))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: text.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          // The API supplies the timestamp, intl only formats it.
                          event.allDay
                              ? 'all day'
                              : formatDayAndClock(event.startsAt),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text('and $hidden more organizers', style: text.bodySmall),
          ),
      ],
    );
  }
}
