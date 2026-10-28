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

import '../data/campus_time.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/empty_state.dart';
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

/// Up next on a phone: timed events not yet over, soonest first, a boosted
/// one first only on a tie. All day events are counted in the hero, never
/// listed, or they would sit on top every day.
List<CampusEvent> upNextOrder(
  List<CampusEvent> events, {
  Set<String> boosted = const {},
  DateTime? now,
}) {
  final moment = now ?? CampusTime.nowUtc();
  final timed = [
    for (final event in events)
      if (!event.allDay && eventEnd(event).isAfter(moment)) event,
  ];
  timed.sort((a, b) {
    final byStart = a.startsAt.compareTo(b.startsAt);
    if (byStart != 0) return byStart;
    final aBoost = boosted.contains(a.uid);
    if (aBoost != boosted.contains(b.uid)) return aBoost ? -1 : 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return timed;
}

/// The Up next hero: events on today, started or not, that are not over. A
/// multi day event on its last day counts.
int upNextToday(List<CampusEvent> events, {DateTime? now}) {
  final moment = now ?? CampusTime.nowUtc();
  final today = CampusTime.dateOf(moment);
  return events
      .where((e) => !CampusTime.dateOf(e.startsAt).isAfter(today) && eventEnd(e).isAfter(moment))
      .length;
}

/// Organizer type drives the header icon.
AppIconKind iconForOrganizer(String name) {
  final n = name.toLowerCase();
  if (n == 'rit') return AppIconKind.school;
  // Athletics fixtures group by sport, so the icon follows the sport.
  if (n.contains('soccer')) return AppIconKind.soccer;
  if (n.contains('volleyball')) return AppIconKind.volleyball;
  if (n.contains('basketball')) return AppIconKind.basketball;
  if (n.contains('hockey')) return AppIconKind.hockey;
  if (n.contains('cross country') || n.contains('track')) {
    return AppIconKind.running;
  }
  if (n.contains('swim') || n.contains('diving')) {
    return AppIconKind.swimming;
  }
  if (n.contains('rowing')) return AppIconKind.rowing;
  if (n.contains('tennis')) return AppIconKind.tennis;
  if (n.contains('lacrosse') ||
      n.contains('baseball') ||
      n.contains('softball')) {
    return AppIconKind.baseball;
  }
  if (n.contains('food') || n.contains('dining')) {
    return AppIconKind.volunteer;
  }
  if (n.contains('council') ||
      n.contains('board') ||
      n.contains('government')) {
    return AppIconKind.groups;
  }
  if (n.contains('residence') || n.contains('housing')) {
    return AppIconKind.housing;
  }
  return AppIconKind.celebration;
}

class EventsCard extends StatelessWidget {
  const EventsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
    this.organizerKey,
    this.compact = false,
    this.boosted = const {},
  });

  final Result<Collection<CampusEvent>> result;

  /// Uids that matched a boost word. Breaks start time ties in Up next.
  final Set<String> boosted;
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
    // one question on a phone, wide keeps its groups
    final upNext = !_scoped && !compact && Insets.phone(context);
    final today = upNext ? upNextToday(events) : eventsToday(events);

    // The club's own name, taken from its events rather than stored on the
    // card, so a club that renames itself is not stuck with the old label.
    final title = _scoped
        ? (events.isEmpty
              ? 'Club events'
              : events.first.organizer ?? 'Club events')
        : (upNext ? 'Up next' : 'Events');

    return CardShell(
      glyph: AppIconKind.events,
      title: title,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      onOpen: onShowAll,
      openLabel: 'opens Events',
      // "Today" is the useful card-level answer. The full feed can span
      // weeks, so its total would look impressive without helping a student
      // decide whether there is anything happening now.
      hero: events.isEmpty
          ? null
          : CardHero(value: '$today', label: 'Today', filled: today > 0),
      child: switch ((result.isPriming, events.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading events'),
        (_, true) => EmptyState(
          kind: EmptyKind.noEvents,
          // A club with nothing on is a different fact from the whole campus
          // being quiet, and saying so avoids looking broken.
          title: _scoped ? 'No club events' : null,
        ),
        _ when compact => _Compact(events: events),
        _ when upNext => _UpNext(events: upNextOrder(events, boosted: boosted)),
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
    // today hands over upcoming events only, so the first is next
    final ordered = [...events]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return EventRow(event: ordered.first, dense: true);
  }
}

/// The next few events, flat, no organizer bars.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.events});

  final List<CampusEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const EmptyState(kind: EmptyKind.noEvents, title: 'No more events');
    return BoundedList(
      itemCount: events.length,
      itemHeight: StatusRow.heightFor(context, dense: true),
      dense: true,
      maxRows: phoneRowCap(context),
      noun: 'events',
      itemBuilder: (context, i) => EventRow(event: events[i], dense: true),
    );
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
      itemHeight: StatusRow.heightFor(context, dense: true),
      dense: true,
      maxRows: phoneRowCap(context),
      noun: 'events',
      onShowAll: onShowAll,
      itemBuilder: (context, i) => EventRow(event: ordered[i], dense: true),
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
      GroupHeader.blockHeight(context, dense: true) +
      StatusRow.heightFor(context, dense: true) * _perGroup;

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
      dense: true,
      maxRows: phoneRowCap(context, reserved: 2),
      noun: 'organizers',
      onShowAll: onShowAll,
      itemBuilder: (context, i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupHeader(
            dense: true,
            icon: iconForOrganizer(ordered[i].key),
            title: ordered[i].key,
            count: ordered[i].value.length,
          ),
          for (final event in ordered[i].value.take(_perGroup))
            EventRow(event: event, dense: true),
        ],
      ),
    );
  }
}
