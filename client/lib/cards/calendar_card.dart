/// A week of events, as a calendar rather than a feed.
///
/// The Events tab already answers "what is on". This answers a different
/// question: **which day**. A list cannot show that a Thursday is empty and a
/// Friday is packed without being read end to end, and that shape is the whole
/// reason to have a calendar at all.
///
/// Seven days starting today, not a calendar month. A month grid of a campus
/// feed is mostly empty cells and past dates, and nobody plans their week from
/// the 3rd of next month.
///
/// Scope follows the spec's module table: all visible events, or one organizer.
library;

import 'package:flutter/material.dart';

import '../data/campus_time.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/empty_state.dart';
import '../widgets/freshness.dart';
import '../widgets/glyph.dart';
import '../widgets/scalloped_badge.dart';
import '../widgets/status_row.dart';
import 'event_row.dart';

/// How many days the strip covers. A week is what people plan over.
const int calendarDays = 7;

/// One day in the strip.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.events,
    required this.isToday,
  });

  /// UTC midnight whose year, month and day are already the campus calendar
  /// date. Read those fields directly: passing this back through
  /// `CampusTime.fieldsOf` applies the offset a second time and lands on the
  /// previous evening, which shifted every cell in the strip back a day.
  final DateTime date;
  final List<CampusEvent> events;
  final bool isToday;
}

/// Bucket events into the next [calendarDays] days, starting today.
///
/// Days with nothing are kept. An empty Thursday is information, and dropping
/// it would collapse the strip into a list again.
List<CalendarDay> calendarWeek(
  List<CampusEvent> events, {
  required DateTime now,
}) {
  final today = CampusTime.dateOf(now);

  final byDate = <String, List<CampusEvent>>{};
  for (final event in events) {
    final key = _key(CampusTime.dateOf(event.startsAt));
    byDate.putIfAbsent(key, () => []).add(event);
  }

  return [
    for (var offset = 0; offset < calendarDays; offset++)
      () {
        final date = today.add(Duration(days: offset));
        final found = byDate[_key(date)] ?? const <CampusEvent>[];
        final ordered = [...found]
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        return CalendarDay(date: date, events: ordered, isToday: offset == 0);
      }(),
  ];
}

String _key(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

const List<String> _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class CalendarCard extends StatefulWidget {
  const CalendarCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
    this.organizerKey,
    this.compact = false,
    this.now,
  });

  final Result<Collection<CampusEvent>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  /// Narrows to one organizer. Null shows everything visible.
  final String? organizerKey;

  final bool compact;

  /// Overridable so the week is deterministic in tests. Production always
  /// passes null and reads the campus clock.
  final DateTime? now;

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  /// Which day's events are listed. Defaults to today, and follows the strip.
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final all = widget.result.value?.data ?? const <CampusEvent>[];
    final events = widget.organizerKey == null
        ? all
        : [
            for (final e in all)
              if (e.organizerKey == widget.organizerKey) e,
          ];

    final week = calendarWeek(events, now: widget.now ?? CampusTime.nowUtc());
    final selected = week[_selected.clamp(0, week.length - 1)];

    final title = widget.organizerKey == null
        ? 'Calendar'
        : (events.isEmpty
              ? 'Club calendar'
              : events.first.organizer ?? 'Club calendar');

    return CardShell(
      glyph: GlyphKind.calendar,
      title: title,
      state: widget.result.state,
      fetchedAt: widget.result.fetchedAt,
      dragHandle: widget.dragHandle,
      // The week's total, not today's: this card exists to show the shape of
      // the week, so the number that matches it is the week's.
      hero: events.isEmpty
          ? null
          : ScallopedBadge(
              value: '${week.fold<int>(0, (n, d) => n + d.events.length)}',
              label: 'THIS WEEK',
              size: 88,
              filled: week.any((d) => d.events.isNotEmpty),
            ),
      child: switch ((widget.result.isPriming, events.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading calendar'),
        (_, true) => EmptyState(
          kind: EmptyKind.noEvents,
          title: widget.organizerKey == null
              ? null
              : 'Nothing from this club this week',
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _WeekStrip(
              week: week,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
            ),
            const SizedBox(height: 12),
            if (!widget.compact)
              Flexible(
                child: selected.events.isEmpty
                    ? _NothingOn(day: selected)
                    : BoundedList(
                        itemCount: selected.events.length,
                        itemHeight: StatusRow.heightFor(context) + 4,
                        noun: 'events',
                        onShowAll: widget.onShowAll,
                        itemBuilder: (context, i) =>
                            EventRow(event: selected.events[i]),
                      ),
              ),
          ],
        ),
      },
    );
  }
}

/// The seven day strip. Each day carries its own count, so an empty day reads
/// as empty rather than as missing.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.week,
    required this.selected,
    required this.onSelect,
  });

  final List<CalendarDay> week;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < week.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _DayCell(
                day: week[i],
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final CalendarDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // CalendarDay.date is already a UTC container for campus wall-date
    // fields. Converting it as an instant would move midnight to the prior day.
    final fields = day.date;
    final busy = day.events.isNotEmpty;

    final background = selected
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.surfaceContainerHigh;

    return Semantics(
      button: true,
      selected: selected,
      // Spoken as a whole rather than as three loose fragments.
      label:
          '${_weekdayName(fields.weekday)} ${fields.day}, '
          '${day.events.length} event${day.events.length == 1 ? '' : 's'}'
          '${day.isToday ? ', today' : ''}',
      child: ExcludeSemantics(
        child: Material(
          elevation: 0,
          color: background,
          borderRadius: Shapes.small,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekdayLetters[fields.weekday - 1],
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${fields.day}',
                    style: text.bodyMedium?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontVariations: day.isToday
                          ? Weights.bold
                          : Weights.medium,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // The count is stated, not implied by a dot's size, so the
                  // difference between one event and six is readable.
                  Text(
                    busy ? '${day.events.length}' : '·',
                    style: text.labelSmall?.copyWith(
                      color: busy
                          ? (selected ? scheme.primary : scheme.onSurface)
                          : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingOn extends StatelessWidget {
  const _NothingOn({required this.day});

  final CalendarDay day;

  @override
  Widget build(BuildContext context) {
    final fields = day.date;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        day.isToday
            ? 'Nothing on today'
            : 'Nothing on ${_weekdayName(fields.weekday)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

String _weekdayName(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];
