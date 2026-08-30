library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/status_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/glyph.dart';
import 'event_row.dart';

List<CampusEvent> _scopedEvents(
  Result<Collection<CampusEvent>> result,
  String? organizerKey,
) {
  final events = result.value?.data ?? const <CampusEvent>[];
  final filtered = organizerKey == null
      ? events
      : events.where((event) => event.organizerKey == organizerKey).toList();
  return filtered.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

String organizerName(
  Result<Collection<CampusEvent>> result,
  String? organizerKey,
) {
  if (organizerKey == null) return 'Club events';
  for (final event in result.value?.data ?? const <CampusEvent>[]) {
    if (event.organizerKey == organizerKey) {
      return event.organizer?.trim().isNotEmpty == true
          ? event.organizer!
          : 'Club events';
    }
  }
  return 'Club events';
}

class ScopedEventsCard extends StatelessWidget {
  const ScopedEventsCard({
    super.key,
    required this.result,
    required this.organizerKey,
    this.compact = false,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<CampusEvent>> result;
  final String? organizerKey;
  final bool compact;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final events = _scopedEvents(result, organizerKey);
    final future = events
        .where(
          (event) => (event.endsAt ?? event.startsAt).isAfter(DateTime.now()),
        )
        .toList();
    final shown = future.isEmpty ? events : future;

    return CardShell(
      title: organizerName(result, organizerKey),
      glyph: GlyphKind.events,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      hero: events.isEmpty
          ? null
          : Text(
              '${events.length} events',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
      child: events.isEmpty
          ? const EmptyState(kind: EmptyKind.noEvents)
          // BoundedList rather than a hardcoded take() plus a bespoke "+N
          // more" button: the cap was a guess, and every other card counts its
          // overflow the same way.
          : BoundedList(
              itemCount: shown.length,
              itemHeight: StatusRow.height,
              noun: 'events',
              onShowAll: onShowAll,
              itemBuilder: (context, index) => EventRow(event: shown[index]),
            ),
    );
  }
}

class EventCalendarCard extends StatefulWidget {
  const EventCalendarCard({
    super.key,
    required this.result,
    this.organizerKey,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<CampusEvent>> result;
  final String? organizerKey;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  @override
  State<EventCalendarCard> createState() => _EventCalendarCardState();
}

class _EventCalendarCardState extends State<EventCalendarCard> {
  int _selectedDay = 0;

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (index) => today.add(Duration(days: index)));
    final events = _scopedEvents(widget.result, widget.organizerKey);
    final byDay = [
      for (final day in days)
        events.where((event) {
          final start = event.startsAt.toLocal();
          return start.year == day.year &&
              start.month == day.month &&
              start.day == day.day;
        }).toList(),
    ];
    final selected = byDay[_selectedDay];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return CardShell(
      title: widget.organizerKey == null
          ? 'Events calendar'
          : '${organizerName(widget.result, widget.organizerKey)} calendar',
      glyph: GlyphKind.events,
      state: widget.result.state,
      fetchedAt: widget.result.fetchedAt,
      dragHandle: widget.dragHandle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: i == _selectedDay
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => setState(() => _selectedDay = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Column(
                            children: [
                              Text(
                                _weekdays[days[i].weekday - 1],
                                style: text.labelSmall,
                              ),
                              const SizedBox(height: 3),
                              Text('${days[i].day}', style: text.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                '${byDay[i].length}',
                                style: text.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (selected.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Text('Nothing scheduled this day', style: text.bodyMedium),
            )
          else
            for (final event in selected.take(4)) EventRow(event: event),
          if (selected.length > 4 && widget.onShowAll != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onShowAll,
                child: Text('+${selected.length - 4} more'),
              ),
            ),
        ],
      ),
    );
  }
}
