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
import '../widgets/bounded_list.dart';

class EventsCard extends StatelessWidget {
  const EventsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<CampusEvent>> result;
  final Widget? dragHandle;

  /// Tap target for the detail view. Not built yet, so this is a no-op.
  final VoidCallback? onShowAll;

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
        _ => _Grouped(events: events, onShowAll: onShowAll),
      },
    );
  }
}

class _Grouped extends StatelessWidget {
  const _Grouped({required this.events, this.onShowAll});

  final List<CampusEvent> events;
  final VoidCallback? onShowAll;

  /// Two events per organizer keeps every group the same height, which lets
  /// BoundedList work out exactly how many fit.
  static const int _maxPerGroup = 2;
  static const double _groupHeight = 84;

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

    return BoundedList(
      itemCount: ordered.length,
      itemHeight: _groupHeight,
      noun: 'organizers',
      onShowAll: onShowAll,
      itemBuilder: (context, i) => RuledRow(
        last: i == ordered.length - 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ordered[i].key.toUpperCase(),
                    style: text.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${ordered[i].value.length}', style: text.labelSmall),
              ],
            ),
            const SizedBox(height: 4),
            for (final event in ordered[i].value.take(_maxPerGroup))
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
                      event.allDay ? 'all day' : formatDayAndClock(event.startsAt),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
