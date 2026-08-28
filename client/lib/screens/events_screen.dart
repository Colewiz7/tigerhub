/// Events tab: the merged feed, grouped by organiser.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import '../widgets/freshness.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key, required this.result});

  final Result<Collection<CampusEvent>> result;

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

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final group = ordered[index];
        return Material(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          borderRadius: Shapes.inner,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.key.toUpperCase(),
                        style: text.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('${group.value.length}', style: text.labelSmall),
                  ],
                ),
                const SizedBox(height: 8),
                for (final event in group.value.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: text.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
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
        );
      },
    );
  }
}
