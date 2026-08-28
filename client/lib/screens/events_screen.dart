/// Events tab: the merged feed, grouped by organizer.
///
/// Density is deliberately low. Past events stay visible but dimmed, so the
/// split between what has happened and what is still to come is readable at a
/// glance.
library;

import 'package:flutter/material.dart';

import '../cards/event_row.dart';
import '../cards/events_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/content_column.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key, required this.result});

  final Result<Collection<CampusEvent>> result;

  static const int _perGroup = 4;

  @override
  Widget build(BuildContext context) {
    if (result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading events');
    }

    final events = result.value?.data ?? const <CampusEvent>[];
    final groups = <String, List<CampusEvent>>{};
    for (final event in events) {
      groups.putIfAbsent(event.organizer ?? 'Other', () => []).add(event);
    }
    final ordered = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return ContentColumn(
      child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final group = ordered[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GroupHeader(
                icon: iconForOrganizer(group.key),
                title: group.key,
                count: group.value.length,
              ),
              for (final event in group.value.take(_perGroup))
                EventRow(event: event),
              if (group.value.length > _perGroup)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    '+${group.value.length - _perGroup} more from this organizer',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
      ),
    );
  }
}
