/// Dining tab: every location, grouped by category.
///
/// Categories come from the server's static config, because TigerCenter
/// publishes none of its own (catId, mapId and mrkId are 0 on all 24, and
/// department is "Dining" for every one).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cards/dining_card.dart';
import '../cards/visiting_chefs_card.dart' show VisitingChefsCard;
import '../data/campus_time.dart';
import '../data/local_backend.dart' show staleGraceMultiplier;
import '../data/sources/food_trucks.dart' show foodTrucksCadence;
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/app_icon.dart';
import '../widgets/jump_list.dart';
import '../widgets/link_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/freshness.dart';
import '../widgets/search_field.dart';
import '../services/preferences.dart';
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
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _openOnly = false;
  bool _pinnedOnly = false;
  Result<Collection<MenuItem>> _features = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<FoodTruck>> _trucks = const Result(
    value: null,
    state: DataState.priming,
  );

  Result<Collection<MenuItem>> _chefs = const Result(
    value: null,
    state: DataState.priming,
  );

  // only a real answer with chefs on today's campus date; the feed is
  // today's, but a cached copy can be yesterday's
  List<MenuItem> _todayChefs(String query) {
    final chefs = _chefs.value;
    if (chefs == null || chefs.availability != Availability.available) {
      return const [];
    }
    final today = CampusTime.wallDate();
    return [
      for (final chef in chefs.data)
        if (chef.name.isNotEmpty &&
            (chef.startsAt == null ||
                DateUtils.isSameDay(CampusTime.fieldsOf(chef.startsAt!), today)) &&
            (query.isEmpty ||
                chef.name.toLowerCase().contains(query) ||
                chef.locationName.toLowerCase().contains(query) ||
                (chef.cuisine?.toLowerCase().contains(query) ?? false)))
          chef,
    ];
  }

  bool get _trucksFresh {
    final trucks = _trucks.value;
    final at = trucks?.lastUpdated;
    if (trucks == null || at == null) return false;
    if (trucks.availability != Availability.available) return false;
    // device clock skew is not handled
    return DateTime.now().difference(at) <= foodTrucksCadence * staleGraceMultiplier;
  }

  StreamSubscription<Result<Collection<FoodTruck>>>? _trucksSub;
  StreamSubscription<Result<Collection<MenuItem>>>? _featuresSub;
  StreamSubscription<Result<Collection<MenuItem>>>? _chefsSub;
  bool _active = true;

  // keeps what it has when a read comes back empty-handed
  void _readChefs() {
    _chefsSub?.cancel();
    _chefsSub = widget.api.visitingChefs().listen((result) {
      if (!mounted) return;
      if (result.value == null && _chefs.value != null) return;
      setState(() => _chefs = result);
    });
  }

  // also the Retry button
  void _readFeatures() {
    _featuresSub?.cancel();
    _featuresSub = widget.api.diningFeatures().listen((result) {
      if (mounted) setState(() => _features = result);
    });
  }

  // local snapshot, swapped in place
  void _readTrucks() {
    _trucksSub?.cancel();
    _trucksSub = widget.api.foodTrucks().listen((result) {
      if (!mounted) return;
      if (result.value == null && _trucks.value != null) return;
      setState(() => _trucks = result);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_active) {
      _readTrucks();
      _readChefs();
    }
    _active = active;
  }

  // shell hands over fresh result each tick
  @override
  void didUpdateWidget(DiningScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.result, widget.result)) {
      _readTrucks();
      _readChefs();
    }
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
    _readTrucks();
    _readChefs();
    _readFeatures();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _trucksSub?.cancel();
    _chefsSub?.cancel();
    _featuresSub?.cancel();
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

    final chefs = _todayChefs(query);

    // cached trucks show at once
    final trucks = [
      if (_trucksFresh)
        for (final truck in _trucks.value!.data)
          if (truck.name.isNotEmpty &&
              (query.isEmpty ||
                  truck.name.toLowerCase().contains(query) ||
                  (truck.location?.toLowerCase().contains(query) ?? false)))
            truck,
    ];
    // chefs, todays trucks, places, then later days
    final today = CampusTime.wallDate();
    final laterTrucks = [
      for (final truck in trucks)
        if (_FoodTrucksGroup.isLater(truck.date, today)) truck,
    ];
    final todayTrucks = [
      for (final truck in trucks)
        if (!_FoodTrucksGroup.isLater(truck.date, today)) truck,
    ];

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
                  if (chefs.isNotEmpty)
                    JumpGroup(
                      label: 'Visiting chefs',
                      icon: AppIconKind.visitingChef,
                      count: chefs.length,
                      builder: (context) => _VisitingChefsGroup(chefs: chefs),
                    ),
                  if (todayTrucks.isNotEmpty)
                    JumpGroup(
                      label: 'Food trucks',
                      icon: AppIconKind.truck,
                      count: todayTrucks.length,
                      builder: (context) => _FoodTrucksGroup(title: 'Food trucks', trucks: todayTrucks),
                    ),
                  JumpGroup(
                    label: 'Today’s menu',
                    icon: AppIconKind.cutlery,
                    count: menuItems.length,
                    builder: (context) => _TodayMenuGroup(
                      result: _features,
                      items: menuItems,
                      filtering: query.isNotEmpty,
                      onRetry: _readFeatures,
                    ),
                  ),
                  if (groups.isEmpty)
                    JumpGroup(
                      label: 'No matches',
                      icon: AppIconKind.notFound,
                      count: 0,
                      builder: (context) => const EmptyState(
                        kind: EmptyKind.notFound,
                        title: 'No matching locations',
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
                  if (laterTrucks.isNotEmpty)
                    JumpGroup(
                      label: 'Upcoming food trucks',
                      icon: AppIconKind.truck,
                      count: laterTrucks.length,
                      builder: (context) => _FoodTrucksGroup(title: 'Upcoming food trucks', trucks: laterTrucks),
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

const orderOnlineLabel = 'Order online';
const checkBalanceLabel = 'Check balance';
final orderOnlineUrl = Uri.parse('https://ondemand.rit.edu/');
final checkBalanceUrl = Uri.parse('https://tigerspend.rit.edu/');

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
          SearchField(
            controller: controller,
            focusNode: focusNode,
            hintText: 'Search dining or today’s menu',
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              LinkButton(label: orderOnlineLabel, url: orderOnlineUrl),
              LinkButton(label: checkBalanceLabel, url: checkBalanceUrl),
            ],
          ),
          const SizedBox(height: 8),
          // chips and count sit on the list's left edge
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Open'),
                  avatar: Icon(AppIconKind.time.of(context), size: 17),
                  selected: openOnly,
                  onSelected: onOpenChanged,
                ),
                FilterChip(
                  label: Text(
                    'Pinned${pinnedCount == 0 ? '' : ' ($pinnedCount)'}',
                  ),
                  avatar: Icon(AppIconKind.pinned.of(context), size: 17),
                  selected: pinnedOnly,
                  onSelected: pinnedCount == 0 ? null : onPinnedChanged,
                ),
                if (filtered) ...[
                  TextButton(onPressed: onClear, child: const Text('Clear all')),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '$resultCount ${resultCount == 1 ? 'place' : 'places'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodTrucksGroup extends StatelessWidget {
  const _FoodTrucksGroup({required this.title, required this.trucks});

  final String title;
  final List<FoodTruck> trucks;

  static bool isLater(String ymd, DateTime today) {
    final date = DateTime.tryParse(ymd);
    if (date == null) return false;
    return DateTime.utc(date.year, date.month, date.day).isAfter(DateTime.utc(today.year, today.month, today.day));
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // campus date, not the devices
  static String _day(String ymd, DateTime today) {
    final date = DateTime.tryParse(ymd);
    if (date == null) return '';
    final days = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    final weekday = _weekdays[DateTime.utc(date.year, date.month, date.day).weekday - 1];
    return '$weekday, ${_months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final today = CampusTime.wallDate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupHeader(
          icon: AppIconKind.truck,
          title: title,
          count: trucks.length,
        ),
        for (final truck in trucks)
          StatusRow(
            key: ValueKey('truck-${truck.date}-${truck.name}'),
            icon: AppIconKind.truck,
            dense: true,
            subtitleMaxLines: null,
            title: truck.name,
            subtitle: [
              _day(truck.date, today),
              if (truck.timeText?.trim().isNotEmpty ?? false) truck.timeText!,
              if (truck.location?.trim().isNotEmpty ?? false) truck.location!,
            ].where((part) => part.isNotEmpty).join(' · '),
          ),
      ],
    );
  }
}

class _VisitingChefsGroup extends StatelessWidget {
  const _VisitingChefsGroup({required this.chefs});

  final List<MenuItem> chefs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // plain text, not the filled bar the other groups use
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Semantics(
            header: true,
            child: Text(
              'Visiting chefs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        for (final chef in chefs)
          StatusRow(
            key: ValueKey('chef-${chef.id}'),
            icon: AppIconKind.visitingChef,
            subtitleMaxLines: null,
            title: chef.name,
            subtitle: [
              [
                if (chef.cuisine?.trim().isNotEmpty ?? false) chef.cuisine!,
                ?VisitingChefsCard.window(chef),
              ].join(' · '),
              chef.locationName,
            ].where((part) => part.isNotEmpty).join('\n'),
          ),
      ],
    );
  }
}

class _TodayMenuGroup extends StatelessWidget {
  const _TodayMenuGroup({
    required this.result,
    required this.items,
    required this.filtering,
    required this.onRetry,
  });

  final Result<Collection<MenuItem>> result;
  final List<MenuItem> items;
  final bool filtering;
  final VoidCallback onRetry;

  // menus in hand always show. without them, a failed fetch or a source
  // that never loaded is a failure, even over a cached empty day
  bool get _failed {
    final value = result.value;
    if (value != null && value.data.isNotEmpty) return false;
    return result.error != null || result.state == DataState.failing || value?.availability == Availability.unavailable;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final quiet = text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (items.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupHeader(
            icon: AppIconKind.cutlery,
            title: 'Today’s published menu',
            count: items.length,
          ),
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
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: Row(
          children: [
            Expanded(child: Text('Couldn’t load menus', style: quiet)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading today’s menu');
    }
    if (filtering) {
      return const EmptyState(kind: EmptyKind.noEvents, title: 'No matching menu items');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Text('Menus not published yet today', style: quiet),
    );
  }

  static AppIconKind _menuIcon(String? category) {
    final value = category?.toLowerCase() ?? '';
    if (value.contains('soup')) return AppIconKind.visitingChef;
    if (value.contains('salad')) return AppIconKind.plant;
    if (value.contains('breakfast')) return AppIconKind.breakfast;
    if (value.contains('dessert') || value.contains('bakery')) {
      return AppIconKind.bakery;
    }
    if (value.contains('visiting')) return AppIconKind.roomService;
    return AppIconKind.menu;
  }
}
