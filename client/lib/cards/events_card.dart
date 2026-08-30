/// Events card.
///
/// No gauges. Grouped by organizer, with each organizer introduced by a tinted
/// header row rather than a line of small uppercase text, because the organizer
/// is a navigation landmark.
///
/// Grouping matters: FoodShare alone is 213 of 921 events, so an ungrouped list
/// reads as one club's feed.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';
import 'event_row.dart';

/// Organizer type drives the header icon.
IconData iconForOrganizer(String name) {
  final n = name.toLowerCase();
  if (n == 'rit') return Icons.school_rounded;
  // Athletics fixtures group by sport, so the icon follows the sport.
  if (n.contains('soccer')) return Icons.sports_soccer_rounded;
  if (n.contains('volleyball')) return Icons.sports_volleyball_rounded;
  if (n.contains('basketball')) return Icons.sports_basketball_rounded;
  if (n.contains('hockey')) return Icons.sports_hockey_rounded;
  if (n.contains('cross country') || n.contains('track')) {
    return Icons.directions_run_rounded;
  }
  if (n.contains('swim') || n.contains('diving')) return Icons.pool_rounded;
  if (n.contains('rowing')) return Icons.rowing_rounded;
  if (n.contains('tennis')) return Icons.sports_tennis_rounded;
  if (n.contains('lacrosse') || n.contains('baseball') || n.contains('softball')) {
    return Icons.sports_baseball_rounded;
  }
  if (n.contains('food') || n.contains('dining')) return Icons.volunteer_activism_rounded;
  if (n.contains('council') || n.contains('board') || n.contains('government')) {
    return Icons.groups_rounded;
  }
  if (n.contains('residence') || n.contains('housing')) return Icons.home_rounded;
  return Icons.celebration_rounded;
}

class EventsCard extends StatelessWidget {
  const EventsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<CampusEvent>> result;
  final Widget? dragHandle;
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

  /// One event under each header keeps every group the same height, which is
  /// what lets BoundedList work out exactly how many fit. Density is meant to
  /// be low here: the Events tab is where the full feed lives.
  static const int _perGroup = 1;
  static double get _groupHeight =>
      GroupHeader.height + GroupHeader.gap + StatusRow.height * _perGroup;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CampusEvent>>{};
    for (final event in events) {
      groups.putIfAbsent(event.organizer ?? 'Other', () => []).add(event);
    }

    // Busiest organizers first, so the card leads with what is actually on.
    final ordered = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return BoundedList(
      itemCount: ordered.length,
      itemHeight: _groupHeight,
      noun: 'organizers',
      onShowAll: onShowAll,
      itemBuilder: (context, i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupHeader(
            icon: iconForOrganizer(ordered[i].key),
            title: ordered[i].key,
            count: ordered[i].value.length,
          ),
          for (final event in ordered[i].value.take(_perGroup))
            EventRow(event: event),
        ],
      ),
    );
  }
}
