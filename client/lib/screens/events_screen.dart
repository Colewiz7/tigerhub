/// Events tab: the merged feed, grouped by organizer, filtered by preference.
///
/// Nothing is ever silently dropped. Each group ends with a hidden count that
/// expands in place, and the whole tab ends with the total.
library;

import 'package:flutter/material.dart';

import '../cards/event_row.dart';
import '../cards/events_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/event_filter.dart';
import '../services/preferences.dart';
import '../widgets/content_column.dart';
import '../widgets/freshness.dart';
import '../widgets/hidden_footer.dart';
import '../widgets/status_row.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.result});

  final Result<Collection<CampusEvent>> result;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _prefs = Preferences.instance;
  final _expanded = <String>{};

  static const int _perGroup = 4;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading events');
    }

    final events = widget.result.value?.data ?? const <CampusEvent>[];
    final filtered = filterEvents(events, _prefs);
    final text = Theme.of(context).textTheme;

    return ContentColumn(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: filtered.groups.length + 1,
        itemBuilder: (context, index) {
          if (index == filtered.groups.length) {
            return _TotalFooter(hidden: filtered.hiddenTotal);
          }

          final group = filtered.groups[index];
          final open = _expanded.contains(group.organizer);
          final shown = group.visible.take(_perGroup).toList();
          final overflow = group.visible.length - shown.length;

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GroupHeader(
                  icon: iconForOrganizer(group.organizer),
                  title: group.organizer,
                  count: group.visible.length,
                ),
                for (final item in shown)
                  EventRow(event: item.event, boosted: item.boosted),
                if (overflow > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2, bottom: 4),
                    child: Text(
                      '+$overflow more from this organizer',
                      style: text.bodySmall,
                    ),
                  ),
                HiddenFooter(
                  count: group.hiddenCount,
                  expanded: open,
                  onToggle: () => setState(() {
                    open
                        ? _expanded.remove(group.organizer)
                        : _expanded.add(group.organizer);
                  }),
                ),
                if (open)
                  for (final item in group.hidden)
                    EventRow(event: item.event, forceDimmed: true),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TotalFooter extends StatelessWidget {
  const _TotalFooter({required this.hidden});

  final int hidden;

  @override
  Widget build(BuildContext context) {
    if (hidden <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '$hidden events hidden by your filters. Adjust them in Settings.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
