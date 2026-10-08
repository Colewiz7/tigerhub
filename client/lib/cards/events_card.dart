/// Events card.
///
/// No gauges. Grouped by organizer, with each organizer introduced by a tinted
/// header row rather than a line of small uppercase text, because the organizer
/// is a navigation landmark.
///
/// Grouping matters: FoodShare alone is 213 of 921 events, so an ungrouped list
/// reads as one club's feed.
library;

import '../data/campus_time.dart';
import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/glyph.dart';
import '../widgets/freshness.dart';
import '../widgets/scalloped_badge.dart';
import '../widgets/status_row.dart';
import 'event_row.dart';

/// Count events on the viewer's current calendar day.
///
/// Event instants arrive with an offset. "Today" is the campus calendar day
/// (America/New_York), the same day the event times are shown in.
int eventsToday(List<CampusEvent> events, {DateTime? now}) {
  final today = CampusTime.dateOf(now ?? CampusTime.nowUtc());
  return events
      .where((event) => CampusTime.dateOf(event.startsAt) == today)
      .length;
}

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
  if (n.contains('swim') || n.contains('diving')) {
    return Icons.pool_rounded;
  }
  if (n.contains('rowing')) return Icons.rowing_rounded;
  if (n.contains('tennis')) return Icons.sports_tennis_rounded;
  if (n.contains('lacrosse') ||
      n.contains('baseball') ||
      n.contains('softball')) {
    return Icons.sports_baseball_rounded;
  }
  if (n.contains('food') || n.contains('dining')) {
    return Icons.volunteer_activism_rounded;
  }
  if (n.contains('council') ||
      n.contains('board') ||
      n.contains('government')) {
    return Icons.groups_rounded;
  }
  if (n.contains('residence') || n.contains('housing')) {
    return Icons.home_rounded;
  }
  return Icons.celebration_rounded;
}

class EventsCard extends StatelessWidget {
  const EventsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
    this.organizerKey,
    this.compact = false,
  });

  final Result<Collection<CampusEvent>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  /// Narrows this card to one organizer, which is what makes a club events
  /// card different from the general one. Null shows everything, grouped.
  ///
  /// One renderer serves both, as the spec allows, but they stay separate
  /// templates in the card library: "show me one club" is the common task and
  /// should not require walking through a scope editor to reach.
  final String? organizerKey;
  final bool compact;

  bool get _scoped => organizerKey != null;

  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <CampusEvent>[];
    final events = _scoped
        ? [
            for (final e in all)
              if (e.organizerKey == organizerKey) e,
          ]
        : all;
    final today = eventsToday(events);

    // The club's own name, taken from its events rather than stored on the
    // card, so a club that renames itself is not stuck with the old label.
    final title = _scoped
        ? (events.isEmpty
              ? 'Club events'
              : events.first.organizer ?? 'Club events')
        : 'Events';

    return CardShell(
      glyph: GlyphKind.events,
      title: title,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      // "Today" is the useful card-level answer. The full feed can span
      // weeks, so its total would look impressive without helping a student
      // decide whether there is anything happening now.
      hero: events.isEmpty
          ? null
          : ScallopedBadge(
              value: '$today',
              label: 'TODAY',
              size: 88,
              filled: today > 0,
            ),
      child: switch ((result.isPriming, events.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading events'),
        (_, true) => EmptyState(
          kind: EmptyKind.noEvents,
          // A club with nothing on is a different fact from the whole campus
          // being quiet, and saying so avoids looking broken.
          title: _scoped ? 'Nothing from this club yet' : null,
        ),
        _ when compact => _Compact(events: events),
        // Grouping by organizer is pointless when they are all one organizer.
        _ when _scoped => _Flat(events: events, onShowAll: onShowAll),
        _ => _Grouped(events: events, onShowAll: onShowAll),
      },
    );
  }
}

class _Compact extends StatelessWidget {
  const _Compact({required this.events});

  final List<CampusEvent> events;

  @override
  Widget build(BuildContext context) {
    final now = CampusTime.nowUtc();
    final ordered = [...events]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final next = ordered
        .where((event) => (event.endsAt ?? event.startsAt).isAfter(now))
        .firstOrNull;
    return EventRow(event: next ?? ordered.first);
  }
}

/// A single club's events, in time order.
///
/// No group headers: every row shares one organizer, so a header per row would
/// repeat the card's own title down the page.
class _Flat extends StatelessWidget {
  const _Flat({required this.events, this.onShowAll});

  final List<CampusEvent> events;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final ordered = [...events]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return BoundedList(
      itemCount: ordered.length,
      itemHeight: StatusRow.heightFor(context),
      noun: 'events',
      onShowAll: onShowAll,
      itemBuilder: (context, i) => EventRow(event: ordered[i]),
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
  static double _groupHeightFor(BuildContext context) =>
      GroupHeader.height +
      GroupHeader.gap +
      StatusRow.heightFor(context) * _perGroup;

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
      itemHeight: _groupHeightFor(context),
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
