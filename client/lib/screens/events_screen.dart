/// Events tab: the merged feed, grouped by organizer, filtered by preference.
///
/// Nothing is ever silently dropped. Each group ends with a hidden count that
/// expands in place, and the whole tab ends with the total.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cards/event_row.dart';
import '../cards/events_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/event_filter.dart';
import '../services/preferences.dart';
import '../data/campus_time.dart';
import '../widgets/jump_list.dart';
import '../widgets/empty_state.dart';
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
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _todayOnly = false;

  static const int _perGroup = 4;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _search.dispose();
    _searchFocus.dispose();
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

    final query = _search.text.trim().toLowerCase();
    final today = CampusTime.dateOf(CampusTime.nowUtc());
    final events = (widget.result.value?.data ?? const <CampusEvent>[]).where((
      event,
    ) {
      if (_todayOnly) {
        final date = CampusTime.dateOf(event.startsAt.toUtc());
        if (date != today) return false;
      }
      if (query.isEmpty) return true;
      return event.title.toLowerCase().contains(query) ||
          (event.organizer?.toLowerCase().contains(query) ?? false) ||
          (event.location?.toLowerCase().contains(query) ?? false) ||
          (event.eventType?.toLowerCase().contains(query) ?? false);
    }).toList();
    final filtered = filterEvents(
      events,
      _prefs,
      revealKeywordMatches: query.isNotEmpty,
    );
    final text = Theme.of(context).textTheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
          _search.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _search.text.length,
          );
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _EventFilters(
              controller: _search,
              focusNode: _searchFocus,
              todayOnly: _todayOnly,
              count: filtered.groups.fold<int>(
                0,
                (n, group) => n + group.visible.length,
              ),
              onQueryChanged: (_) => setState(() {}),
              onTodayChanged: (value) => setState(() => _todayOnly = value),
              onClear: () => setState(() {
                _search.clear();
                _todayOnly = false;
              }),
            ),
            Expanded(
              child: filtered.groups.isEmpty
                  ? const EmptyState(
                      kind: EmptyKind.notFound,
                      title: 'No events match these filters',
                      detail: 'Clear a filter or try another search.',
                      compact: false,
                    )
                  : JumpList(
                      footer: _TotalFooter(hidden: filtered.hiddenTotal),
                      groups: [
                        for (final group in filtered.groups)
                          JumpGroup(
                            label: group.organizer,
                            icon: iconForOrganizer(group.organizer),
                            count: group.visible.length,
                            builder: (context) {
                              final open = _expanded.contains(group.organizer);
                              final shown = group.visible
                                  .take(_perGroup)
                                  .toList();
                              final overflow =
                                  group.visible.length - shown.length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GroupHeader(
                                    icon: iconForOrganizer(group.organizer),
                                    title: group.organizer,
                                    count: group.visible.length,
                                  ),
                                  for (final item in shown)
                                    EventRow(
                                      event: item.event,
                                      boosted: item.boosted,
                                    ),
                                  if (overflow > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        top: 2,
                                        bottom: 4,
                                      ),
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
                                      EventRow(
                                        event: item.event,
                                        forceDimmed: true,
                                      ),
                                ],
                              );
                            },
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

class _EventFilters extends StatelessWidget {
  const _EventFilters({
    required this.controller,
    required this.focusNode,
    required this.todayOnly,
    required this.count,
    required this.onQueryChanged,
    required this.onTodayChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool todayOnly;
  final int count;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onTodayChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final filtered = controller.text.isNotEmpty || todayOnly;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search events, clubs, or places',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Today'),
                avatar: const Icon(Icons.today_rounded, size: 17),
                selected: todayOnly,
                onSelected: onTodayChanged,
              ),
              Text(
                '$count ${count == 1 ? 'event' : 'events'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (filtered)
                TextButton(onPressed: onClear, child: const Text('Clear all')),
            ],
          ),
        ],
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
