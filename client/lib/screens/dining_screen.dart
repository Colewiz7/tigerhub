/// Dining tab: every location, grouped by category.
///
/// Categories come from the server's static config, because TigerCenter
/// publishes none of its own (catId, mapId and mrkId are 0 on all 24, and
/// department is "Dining" for every one).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cards/dining_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/jump_list.dart';
import '../widgets/empty_state.dart';
import '../widgets/freshness.dart';
import '../services/preferences.dart';
import '../services/subscriptions.dart';
import '../widgets/status_row.dart';

class DiningScreen extends StatefulWidget {
  const DiningScreen({super.key, required this.result, required this.api});

  final Result<Collection<DiningLocation>> result;
  final ApiClient api;

  @override
  State<DiningScreen> createState() => _DiningScreenState();
}

class _DiningScreenState extends State<DiningScreen> {
  final _prefs = Preferences.instance;
  final _subscriptions = Subscriptions();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _openOnly = false;
  bool _pinnedOnly = false;
  Result<Collection<MenuItem>> _features = const Result(
    value: null,
    state: DataState.priming,
  );

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
    _subscriptions.add(
      widget.api.diningFeatures().listen((result) {
        if (mounted) setState(() => _features = result);
      }),
    );
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _subscriptions.dispose();
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
      return const PrimingPlaceholder(label: 'Loading dining hours');
    }

    final query = _search.text.trim().toLowerCase();
    final locations = (widget.result.value?.data ?? const <DiningLocation>[])
        .where((location) {
          if (_openOnly && !location.isOpen) return false;
          if (_pinnedOnly && !_prefs.isPinned(location.id)) return false;
          if (query.isEmpty) return true;
          return location.name.toLowerCase().contains(query) ||
              location.categoryName.toLowerCase().contains(query) ||
              (location.summary?.toLowerCase().contains(query) ?? false);
        })
        .toList();
    final groups = groupByCategory(locations, pinned: _prefs.pinnedDining);
    final allMenuItems = [...(_features.value?.data ?? const <MenuItem>[])]
      ..sort((a, b) {
        final byLocation = a.locationName.compareTo(b.locationName);
        if (byLocation != 0) return byLocation;
        final byCategory = (a.category ?? '').compareTo(b.category ?? '');
        return byCategory != 0 ? byCategory : a.name.compareTo(b.name);
      });
    final menuItems = query.isEmpty
        ? allMenuItems
        : allMenuItems
              .where(
                (item) =>
                    item.name.toLowerCase().contains(query) ||
                    item.locationName.toLowerCase().contains(query) ||
                    (item.category?.toLowerCase().contains(query) ?? false),
              )
              .toList();

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
            _DiningFilters(
              controller: _search,
              focusNode: _searchFocus,
              openOnly: _openOnly,
              pinnedOnly: _pinnedOnly,
              pinnedCount: _prefs.pinnedDining.length,
              resultCount: locations.length,
              onQueryChanged: (_) => setState(() {}),
              onOpenChanged: (value) => setState(() => _openOnly = value),
              onPinnedChanged: (value) => setState(() => _pinnedOnly = value),
              onClear: () => setState(() {
                _search.clear();
                _openOnly = false;
                _pinnedOnly = false;
              }),
            ),
            Expanded(
              child: JumpList(
                groups: [
                  JumpGroup(
                    label: 'Today’s menu',
                    icon: Icons.local_dining_rounded,
                    count: menuItems.length,
                    builder: (context) => _TodayMenuGroup(
                      result: _features,
                      items: menuItems,
                      filtering: query.isNotEmpty,
                    ),
                  ),
                  if (groups.isEmpty)
                    JumpGroup(
                      label: 'No matches',
                      icon: Icons.search_off_rounded,
                      count: 0,
                      builder: (context) => const EmptyState(
                        kind: EmptyKind.notFound,
                        title: 'No dining locations match these filters',
                        detail: 'Clear a filter or try a different search.',
                        compact: false,
                      ),
                    )
                  else
                    for (final group in groups)
                      JumpGroup(
                        label: group.key,
                        icon: iconForCategory(group.value.first.category),
                        count: group.value.where((l) => l.isOpen).length,
                        builder: (context) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GroupHeader(
                              icon: iconForCategory(group.value.first.category),
                              title: group.key,
                              count: group.value.where((l) => l.isOpen).length,
                            ),
                            for (final location in group.value)
                              DiningRow(location: location, api: widget.api),
                          ],
                        ),
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

class _DiningFilters extends StatelessWidget {
  const _DiningFilters({
    required this.controller,
    required this.focusNode,
    required this.openOnly,
    required this.pinnedOnly,
    required this.pinnedCount,
    required this.resultCount,
    required this.onQueryChanged,
    required this.onOpenChanged,
    required this.onPinnedChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool openOnly;
  final bool pinnedOnly;
  final int pinnedCount;
  final int resultCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<bool> onPinnedChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final filtered = controller.text.isNotEmpty || openOnly || pinnedOnly;
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
              hintText: 'Search dining or today’s menu',
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
                label: const Text('Open now'),
                avatar: const Icon(Icons.schedule_rounded, size: 17),
                selected: openOnly,
                onSelected: onOpenChanged,
              ),
              FilterChip(
                label: Text(
                  'Pinned${pinnedCount == 0 ? '' : ' ($pinnedCount)'}',
                ),
                avatar: const Icon(Icons.push_pin_rounded, size: 17),
                selected: pinnedOnly,
                onSelected: pinnedCount == 0 ? null : onPinnedChanged,
              ),
              Text(
                '$resultCount ${resultCount == 1 ? 'place' : 'places'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (filtered) ...[
                TextButton(onPressed: onClear, child: const Text('Clear all')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayMenuGroup extends StatelessWidget {
  const _TodayMenuGroup({
    required this.result,
    required this.items,
    required this.filtering,
  });

  final Result<Collection<MenuItem>> result;
  final List<MenuItem> items;
  final bool filtering;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupHeader(
          icon: Icons.local_dining_rounded,
          title: 'Today’s published menu',
          count: items.length,
        ),
        if (result.isPriming)
          const PrimingPlaceholder(label: 'Loading today’s menu')
        else if (items.isEmpty)
          EmptyState(
            kind: EmptyKind.noEvents,
            title: filtering
                ? 'No published menu items match this search'
                : 'No menu features are published today',
            detail: filtering
                ? 'Dining locations are filtered by the same search.'
                : 'Location hours and individual menus are still available below.',
          )
        else
          for (final item in items)
            StatusRow(
              icon: _menuIcon(item.category),
              title: item.name,
              subtitle: [
                if (item.category?.trim().isNotEmpty ?? false) item.category!,
                item.locationName,
              ].join(' · '),
            ),
      ],
    );
  }

  static IconData _menuIcon(String? category) {
    final value = category?.toLowerCase() ?? '';
    if (value.contains('soup')) return Icons.soup_kitchen_rounded;
    if (value.contains('salad')) return Icons.eco_rounded;
    if (value.contains('breakfast')) return Icons.egg_alt_rounded;
    if (value.contains('dessert') || value.contains('bakery')) {
      return Icons.bakery_dining_rounded;
    }
    if (value.contains('visiting')) return Icons.room_service_rounded;
    return Icons.restaurant_menu_rounded;
  }
}
