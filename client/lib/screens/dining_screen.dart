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
import '../data/chef_family.dart';
import '../data/chef_listing.dart';
import '../data/dining_layout.dart';
import '../data/dining_sections.dart';
import '../data/static_config.dart';
import '../data/local_backend.dart' show staleGraceMultiplier;
import '../data/sources/food_trucks.dart' show foodTrucksCadence;
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/clipboard.dart';
import '../widgets/app_icon.dart';
import '../widgets/chef_details.dart';
import '../widgets/context_actions.dart';
import '../widgets/dining_actions.dart';
import '../widgets/dining_group_editor.dart';
import '../widgets/inset_group.dart';
import '../widgets/segmented_picker.dart';
import '../services/open_link.dart';
import '../widgets/jump_list.dart';
import '../widgets/empty_state.dart';
import '../widgets/freshness.dart';
import '../widgets/search_field.dart';
import '../services/preferences.dart';
import '../theme/tokens.dart';
import '../widgets/status_row.dart';

enum DiningView {
  openNow('Open now'),
  favorites('Favorites'),
  all('All');

  const DiningView(this.label);

  final String label;
}

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
  DiningView? _view;
  AppIconKind? _type;
  bool _editing = false;
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
      for (final chef in listedChefs(chefs.data))
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

  // the feed lists chefs for today and every one has ended
  bool get _chefsEnded {
    final chefs = _chefs.value;
    if (chefs == null || chefs.availability != Availability.available) return false;
    final today = CampusTime.wallDate();
    return chefsAllEnded([
      for (final chef in chefs.data)
        if (chef.name.isNotEmpty && (chef.startsAt == null || DateUtils.isSameDay(CampusTime.fieldsOf(chef.startsAt!), today))) chef,
    ]);
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
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _trucksSub?.cancel();
    _chefsSub?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setLayout(DiningLayout layout) => _prefs.setDiningLayout(layout);

  Future<void> _renameGroup(ResolvedGroup group, List<GroupDef> defaults) async {
    final name = await promptGroupName(context, title: 'Rename group', initial: group.name);
    if (name == null) return;
    final defaultName = defaults.where((g) => g.id == group.id).map((g) => g.name).firstOrNull ?? '';
    await _setLayout(_prefs.diningLayout.rename(group.id, name, defaultName: defaultName));
  }

  Future<void> _newGroup() async {
    final name = await promptGroupName(context, title: 'New group');
    if (name == null) return;
    await _setLayout(_prefs.diningLayout.addCustom(name));
  }

  void _deleteGroup(ResolvedGroup group) {
    final before = _prefs.diningLayout;
    showFeedback(
      context,
      'Deleted ${group.name}',
      action: SnackBarAction(label: 'Undo', onPressed: () => _setLayout(before)),
    );
    _setLayout(before.removeCustom(group.id));
  }

  // Pinned is not a group, so it has no header controls
  List<JumpGroup> _editGroups(DiningSections sections, List<GroupDef> defaults) {
    final order = _prefs.diningLayout.groupOrder(defaults);
    return [
      if (sections.pinned.isNotEmpty)
        JumpGroup(
          label: 'Pinned',
          icon: AppIconKind.pinned,
          count: 0,
          builder: (context) => _PlaceSection(title: 'Pinned', places: sections.pinned, api: widget.api, editing: true),
        ),
      for (final section in sections.groups)
        JumpGroup(
          label: section.group.name,
          icon: AppIconKind.dining,
          count: 0,
          builder: (context) {
            final group = section.group;
            final at = order.indexOf(group.id);
            final movable = group.id != otherGroupId;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EditGroupHeader(
                  name: group.name,
                  onRename: () => _renameGroup(group, defaults),
                  onUp: movable && at > 0 ? () => _setLayout(_prefs.diningLayout.moveGroup(group.id, -1, defaults)) : null,
                  onDown: movable && at < order.length - 2 ? () => _setLayout(_prefs.diningLayout.moveGroup(group.id, 1, defaults)) : null,
                  onDelete: group.isDefault ? null : () => _deleteGroup(group),
                ),
                InsetGroup(
                  children: [
                    for (final location in section.places)
                      DiningRow(
                        key: ValueKey('place-${location.id}'),
                        location: location,
                        api: widget.api,
                        grouped: true,
                        onMove: () => showMoveToGroupSheet(context, location),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      JumpGroup(
        label: 'New group',
        icon: AppIconKind.add,
        count: 0,
        builder: (context) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _newGroup,
            icon: AppIcon(AppIconKind.add, size: 18, color: Theme.of(context).colorScheme.primary),
            label: const Text('New group'),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading dining hours');
    }

    final query = _search.text.trim().toLowerCase();
    final everything = widget.result.value?.data ?? const <DiningLocation>[];
    // Open now unless nothing is open, so the tab never opens on an empty list
    final anyOpen = everything.any((l) => l.isOpen && !_prefs.isHidden(l.id));
    final view = _view ?? (anyOpen ? DiningView.openNow : DiningView.all);
    final types = _typesIn(everything);
    final type = types.contains(_type) ? _type : null;
    final locations = everything.where((location) {
      if (view == DiningView.openNow && !location.isOpen) return false;
      if (view == DiningView.favorites && !_prefs.isPinned(location.id)) return false;
      if (type != null && iconForVenue(location.name) != type) return false;
      if (query.isEmpty) return true;
      return location.name.toLowerCase().contains(query) ||
          location.categoryName.toLowerCase().contains(query) ||
          (location.summary?.toLowerCase().contains(query) ?? false);
    }).toList();
    final config = StaticConfig.loadedOrNull;
    final defaults = config?.diningGroups ?? const <GroupDef>[];
    final sections = buildDiningSections(
      locations: _editing ? everything : locations,
      layout: _prefs.diningLayout,
      defaults: defaults,
      defaultGroupOf: config?.diningGroupFor ?? (_) => otherGroupId,
      pinned: _prefs.pinnedDining.toList(),
      hidden: _prefs.hiddenDining,
      // only All lists hidden places
      showHidden: !_editing && view == DiningView.all,
      keepEmpty: _editing,
    );
    final chefs = _todayChefs(query);
    final endedChefs = query.isEmpty && _chefsEnded;
    final nextChef = _chefs.value is ChefCollection ? (_chefs.value as ChefCollection).next : null;

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
            _DiningToolbar(
              controller: _search,
              focusNode: _searchFocus,
              editing: _editing,
              view: view,
              types: types,
              type: type,
              onQueryChanged: (_) => setState(() {}),
              onViewChanged: (value) => setState(() => _view = value),
              onTypeChanged: (value) => setState(() => _type = value),
              onEditChanged: (value) => setState(() => _editing = value),
            ),
            Expanded(
              // long-press means nothing while editing, the rows carry buttons
              child: ContextActionsScope(
                enabled: !_editing,
                child: JumpList(
                  groups: _editing ? _editGroups(sections, defaults) : [

                  if (chefs.isEmpty && endedChefs)
                    JumpGroup(
                      label: 'Visiting chefs',
                      icon: AppIconKind.visitingChef,
                      count: 0,
                      builder: (context) => _NoMoreChefsGroup(next: nextChef),
                    ),
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
                  if (sections.visibleCount == 0 && sections.hidden.isEmpty)
                    JumpGroup(
                      label: 'No matches',
                      icon: AppIconKind.notFound,
                      count: 0,
                      builder: (context) => EmptyState(
                        kind: query.isEmpty && type == null ? (view == DiningView.favorites ? EmptyKind.notFound : EmptyKind.allClosed) : EmptyKind.notFound,
                        title: query.isEmpty && type == null ? (view == DiningView.favorites ? 'No favorites' : 'All closed') : 'No matching locations',
                        compact: false,
                      ),
                    ),
                  if (sections.pinned.isNotEmpty)
                    JumpGroup(
                      label: 'Pinned',
                      icon: AppIconKind.pinned,
                      count: sections.pinned.where((l) => l.isOpen).length,
                      builder: (context) => _PlaceSection(title: 'Pinned', places: sections.pinned, api: widget.api),
                    ),
                  for (final section in sections.groups)
                    JumpGroup(
                      label: section.group.name,
                      icon: AppIconKind.dining,
                      count: section.places.where((l) => l.isOpen).length,
                      builder: (context) => _PlaceSection(title: section.group.name, places: section.places, api: widget.api),
                    ),
                  if (laterTrucks.isNotEmpty)
                    JumpGroup(
                      label: 'Upcoming food trucks',
                      icon: AppIconKind.truck,
                      count: laterTrucks.length,
                      builder: (context) => _FoodTrucksGroup(title: 'Upcoming food trucks', trucks: laterTrucks),
                    ),
                  if (sections.hidden.isNotEmpty)
                    JumpGroup(
                      label: 'Hidden',
                      icon: AppIconKind.hidden,
                      count: 0,
                      builder: (context) => _HiddenSection(places: sections.hidden, api: widget.api),
                    ),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceSection extends StatelessWidget {
  const _PlaceSection({required this.title, required this.places, required this.api, this.editing = false});

  final bool editing;
  final String title;
  final List<DiningLocation> places;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        InsetGroup(
          children: [
            for (final location in places)
              DiningRow(
                key: ValueKey('place-${location.id}'),
                location: location,
                api: api,
                grouped: true,
                onMove: editing ? () => showMoveToGroupSheet(context, location) : null,
              ),
          ],
        ),
      ],
    );
  }
}

// collapsed until opened, so hidden places stay out of the way
class _HiddenSection extends StatefulWidget {
  const _HiddenSection({required this.places, required this.api});

  final List<DiningLocation> places;
  final ApiClient api;

  @override
  State<_HiddenSection> createState() => _HiddenSectionState();
}

class _HiddenSectionState extends State<_HiddenSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: 'Hidden (${widget.places.length})',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: Shapes.inner,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hidden (${widget.places.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    RotatedBox(
                      quarterTurns: _open ? 2 : 0,
                      child: AppIcon(AppIconKind.expand, size: 22, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          InsetGroup(
            children: [
              for (final location in widget.places) DiningRow(key: ValueKey('hidden-${location.id}'), location: location, api: widget.api, grouped: true),
            ],
          ),
      ],
    );
  }
}

const orderOnlineLabel = 'Order online';
const checkBalanceLabel = 'Check balance';
final orderOnlineUrl = Uri.parse('https://ondemand.rit.edu/');
final checkBalanceUrl = Uri.parse('https://tigerspend.rit.edu/');

// the venue types in the data, in a fixed order
List<AppIconKind> _typesIn(List<DiningLocation> places) {
  const order = [
    AppIconKind.diningHall,
    AppIconKind.cafe,
    AppIconKind.grocery,
    AppIconKind.bakery,
    AppIconKind.iceCream,
    AppIconKind.smoothie,
    AppIconKind.deli,
    AppIconKind.restaurant,
    AppIconKind.soup,
    AppIconKind.patio,
    AppIconKind.diningOffice,
    AppIconKind.dining,
  ];
  final present = {for (final l in places) iconForVenue(l.name)};
  return [
    for (final kind in order)
      if (present.contains(kind)) kind,
  ];
}

enum _MenuItem { order, balance, edit }

class _DiningToolbar extends StatelessWidget {
  const _DiningToolbar({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.view,
    required this.types,
    required this.type,
    required this.onQueryChanged,
    required this.onViewChanged,
    required this.onTypeChanged,
    required this.onEditChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final DiningView view;
  final List<AppIconKind> types;
  final AppIconKind? type;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<DiningView> onViewChanged;
  final ValueChanged<AppIconKind?> onTypeChanged;
  final ValueChanged<bool> onEditChanged;

  void _picked(BuildContext context, _MenuItem item) {
    switch (item) {
      case _MenuItem.order:
        openOrCopy(context, orderOnlineUrl, label: orderOnlineLabel);
      case _MenuItem.balance:
        openOrCopy(context, checkBalanceUrl, label: checkBalanceLabel);
      case _MenuItem.edit:
        onEditChanged(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (editing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text('Edit groups', style: Theme.of(context).textTheme.titleLarge))),
            TextButton(onPressed: () => onEditChanged(false), child: const Text('Done')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchField(
                  controller: controller,
                  focusNode: focusNode,
                  hintText: 'Search dining',
                  onChanged: onQueryChanged,
                ),
              ),
              PopupMenuButton<_MenuItem>(
                tooltip: 'More',
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: AppIcon(AppIconKind.more, size: 22, color: scheme.onSurface),
                color: scheme.surfaceContainerHighest,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: Shapes.inner),
                onSelected: (item) => _picked(context, item),
                itemBuilder: (context) => [
                  _item(context, _MenuItem.order, orderOnlineLabel, AppIconKind.link),
                  _item(context, _MenuItem.balance, checkBalanceLabel, AppIconKind.card),
                  _item(context, _MenuItem.edit, 'Edit groups', AppIconKind.edit),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8),
            child: SegmentedPicker<DiningView>(
              value: view,
              labels: {for (final v in DiningView.values) v: v.label},
              onChanged: onViewChanged,
            ),
          ),
          if (types.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  for (final kind in types)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(venueTypeLabel(kind)),
                        avatar: AppIcon(kind, size: 17, color: scheme.onSurfaceVariant),
                        showCheckmark: false,
                        selected: type == kind,
                        onSelected: (on) => onTypeChanged(on ? kind : null),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<_MenuItem> _item(BuildContext context, _MenuItem value, String label, AppIconKind icon) => PopupMenuItem(
    value: value,
    height: 48,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Flexible(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
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
        SectionTitle(title),
        InsetGroup(
          children: [
            for (final truck in trucks)
              StatusRow(
                key: ValueKey('truck-${truck.date}-${truck.name}'),
                icon: AppIconKind.truck,
                dense: true,
                grouped: true,
                subtitleMaxLines: null,
                title: truck.name,
                subtitle: [
                  _day(truck.date, today),
                  if (truck.timeText?.trim().isNotEmpty ?? false) truck.timeText!,
                  if (truck.location?.trim().isNotEmpty ?? false) truck.location!,
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
          ],
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
        const SectionTitle('Visiting chefs'),
        InsetGroup(
          children: [
            for (final chef in chefs)
              StatusRow(
                key: ValueKey('chef-${chef.id}'),
                icon: iconForChef(chef),
                grouped: true,
                subtitleMaxLines: null,
                title: chef.name,
                subtitle: ChefDetails.label(
                  VisitingChefsCard.window(chef),
                  chef.locationName,
                ),
                subtitleBuilder: (context, style) => ChefDetails(
                  window: VisitingChefsCard.window(chef),
                  location: chef.locationName,
                  style: style,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NoMoreChefsGroup extends StatelessWidget {
  const _NoMoreChefsGroup({required this.next});

  final UpcomingChef? next;

  @override
  Widget build(BuildContext context) {
    final line = next;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Visiting chefs'),
        InsetGroup(
          children: [
            StatusRow(
              key: const ValueKey('chefs-ended'),
              icon: AppIconKind.visitingChef,
              grouped: true,
              subtitleMaxLines: null,
              title: 'No more chefs today',
              subtitle: line == null ? '' : nextChefLine(line, CampusTime.wallDate()),
            ),
          ],
        ),
      ],
    );
  }
}
