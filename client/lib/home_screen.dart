/// Today tab: the drag and drop reorderable card grid.
///
/// Card order persists locally. Every card paints from cache immediately, so
/// there is no cold start spinner once the app has run at least once.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import 'cards/dining_card.dart';
import 'cards/dashboard_event_cards.dart';
import 'cards/dashboard_campus_cards.dart';
import 'cards/calendar_card.dart';
import 'cards/events_card.dart';
import 'cards/housing_card.dart';
import 'cards/visiting_chefs_card.dart';
import 'config.dart';
import 'models/api_models.dart';
import 'services/api.dart';
import 'services/dashboard.dart';
import 'theme/tokens.dart';

const List<String> _defaultOrder = ['dining', 'events', 'chefs', 'housing'];

/// The icon each module type shows in the card library and the hidden chips.
/// The name comes from `moduleLabels` beside the type itself, so the library
/// and the renderer cannot drift apart.
const Map<ModuleType, IconData> moduleIcons = {
  ModuleType.diningStatus: Icons.restaurant_rounded,
  ModuleType.generalEvents: Icons.event_note_rounded,
  ModuleType.clubEvents: Icons.groups_rounded,
  ModuleType.calendar: Icons.calendar_month_rounded,
  ModuleType.visitingChefs: Icons.restaurant_menu_rounded,
  ModuleType.mailingAddress: Icons.markunread_mailbox_rounded,
  ModuleType.facilityHours: Icons.fitness_center_rounded,
  ModuleType.campusMap: Icons.map_rounded,
};

/// Card height. Cards grow to use spare vertical room, but stop before they
/// get silly.
const double homeMinCardHeight = 560;

/// High enough that a single row fills a large window rather than leaving a
/// band of dead space under it.
const double homeMaxCardHeight = 860;

/// The most columns the width can carry without the cards getting narrow.
int _widthColumns(double width) {
  if (width < 820) return 1;
  if (width < 1300) return 2;
  if (width < 1850) return 3;
  return 4;
}

/// How many columns to actually use, given the height as well as the width.
///
/// Width alone spread the cards into one wide row and left a band of dead
/// space underneath, and with four cards and three columns it stranded the
/// fourth alone on its own row while there was room beside it.
///
/// So among the column counts the width allows, this prefers one that fills
/// the height, then one that leaves no ragged last row. Four cards in a tall
/// window become two by two rather than three and a widow.
int homeGridColumns(double width, double available, int count) {
  final maxColumns = _widthColumns(width);
  if (count <= 1 || available <= 0) return 1;

  int emptyCells(int columns) {
    final rows = (count / columns).ceil();
    return rows * columns - count;
  }

  var best = maxColumns;
  var bestScore = -1;

  for (var columns = maxColumns; columns >= 1; columns--) {
    final rows = (count / columns).ceil();
    final height = available / rows;

    // Only consider layouts whose cards land in the designed range: taller
    // than the minimum they were drawn against, and short enough that the
    // row is not left floating above dead space.
    if (height < homeMinCardHeight || height > homeMaxCardHeight) continue;

    // Prefer a full last row, then the wider layout.
    final score = (emptyCells(columns) == 0 ? 100 : 0) + columns;
    if (score > bestScore) {
      bestScore = score;
      best = columns;
    }
  }

  return best;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.dining,
    required this.events,
    required this.chefs,
    required this.areas,
    required this.onRefresh,
    required this.onGoToTab,
  });

  final ApiClient api;
  final Result<Collection<DiningLocation>> dining;
  final Result<Collection<CampusEvent>> events;
  final Result<Collection<MenuItem>> chefs;
  final Result<Collection<HousingArea>> areas;
  final Future<void> Function() onRefresh;

  /// The "+N more" footers land on the matching tab.
  final ValueChanged<int> onGoToTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();

  List<String> _order = _defaultOrder;

  /// Cards the user has removed. They stay available to re-add.
  List<String> _hidden = const [];

  /// Edit mode reveals the remove buttons and the add row.
  bool _editing = false;
  String? _selectedId;
  Result<Collection<RecreationFacility>> _recreation = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<CampusMapFeature>> _campusMap = const Result(
    value: null,
    state: DataState.priming,
  );
  StreamSubscription<Result<Collection<RecreationFacility>>>? _recreationSub;
  StreamSubscription<Result<Collection<CampusMapFeature>>>? _mapSub;

  @override
  void initState() {
    super.initState();
    _restoreOrder();
    _recreationSub = widget.api.recreation().listen((result) {
      if (mounted) setState(() => _recreation = result);
    });
    _mapSub = widget.api.campusMap().listen((result) {
      if (mounted) setState(() => _campusMap = result);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _recreationSub?.cancel();
    _mapSub?.cancel();
    super.dispose();
  }

  /// Every instance, hidden ones included. The order here is the saved reading
  /// order and is what persists; what is shown is derived from it.
  List<CardInstance> _instances = defaultDashboard;

  Future<void> _restoreOrder() async {
    // One source of truth. Both this screen and the shell used to read and
    // write the same two preference keys independently, which is how they
    // could disagree about what was hidden.
    final loaded = await DashboardStore.load();
    if (!mounted) return;
    setState(() {
      _instances = loaded;
      _syncFromInstances();
    });
  }

  void _syncFromInstances() {
    _order = [
      for (final card in _instances)
        if (!card.hidden) card.id,
    ];
    _hidden = [
      for (final card in _instances)
        if (card.hidden) card.id,
    ];
  }

  CardInstance? _instance(String id) {
    for (final card in _instances) {
      if (card.id == id) return card;
    }
    return null;
  }

  Future<void> _persist() async {
    // Saved order follows the visible order, with hidden cards kept where they
    // were so unhiding one puts it back rather than at the end.
    final byId = {for (final card in _instances) card.id: card};
    final rebuilt = <CardInstance>[
      for (final id in _order)
        if (byId[id] != null) byId[id]!.copyWith(hidden: false),
    ];
    for (final card in _instances) {
      if (_order.contains(card.id)) continue;
      rebuilt.add(card.copyWith(hidden: true));
    }
    _instances = rebuilt;
    await DashboardStore.save(rebuilt);
  }

  void _removeCard(String id) {
    setState(() {
      _order = _order.where((c) => c != id).toList();
      _hidden = [..._hidden, id];
    });
    _persist();
  }

  void _addCard(String id) {
    setState(() {
      _hidden = _hidden.where((c) => c != id).toList();
      _order = [..._order, id];
    });
    _persist();
  }

  Future<void> _addModule(ModuleType type) async {
    final base = type.id;
    var index = 0;
    while (_instances.any((card) => card.id == '$base-$index')) {
      index++;
    }
    final card = CardInstance(
      id: '$base-$index',
      type: type,
      size: (supportedSizes[type] ?? const [CardSize.standard]).first,
    );
    setState(() {
      _instances = [..._instances, card];
      _order = [..._order, card.id];
      _selectedId = card.id;
    });
    await _persist();
  }

  Future<void> _updateCard(CardInstance updated) async {
    setState(() {
      _instances = [
        for (final card in _instances)
          if (card.id == updated.id) updated else card,
      ];
    });
    await _persist();
  }

  void _moveCard(String id, int delta) {
    final from = _order.indexOf(id);
    final to = (from + delta).clamp(0, _order.length - 1);
    if (from < 0 || from == to) return;
    setState(() {
      final next = [..._order];
      final moved = next.removeAt(from);
      next.insert(to, moved);
      _order = next;
    });
    _persist();
  }

  List<({String key, String name})> get _organizers {
    final found = <String, String>{};
    for (final event in widget.events.value?.data ?? const <CampusEvent>[]) {
      final key = event.organizerKey;
      if (key == null || key.isEmpty) continue;
      found[key] = event.organizer ?? key;
    }
    final values = [
      for (final entry in found.entries) (key: entry.key, name: entry.value),
    ];
    values.sort((a, b) => a.name.compareTo(b.name));
    return values;
  }

  List<({String key, String name})> get _diningCategories {
    final found = <String, String>{};
    for (final location
        in widget.dining.value?.data ?? const <DiningLocation>[]) {
      found[location.category] = location.categoryName;
    }
    final values = [
      for (final entry in found.entries) (key: entry.key, name: entry.value),
    ];
    values.sort((a, b) => a.name.compareTo(b.name));
    return values;
  }

  List<({String key, String name})> get _facilities => [
    for (final facility
        in _recreation.value?.data ?? const <RecreationFacility>[])
      (key: facility.name, name: facility.name),
  ];

  Widget _cardFor(String id, bool showDragHandle) {
    final card = _instance(id);
    if (card == null) return const SizedBox.shrink();
    return _moduleFor(card, showDragHandle);
  }

  /// One module type to one widget. This is the seam the spec's later stages
  /// hang off: adding a card type is a case here plus an entry in the library,
  /// not a change to how the grid works.
  Widget _moduleFor(CardInstance card, bool showDragHandle) =>
      switch (card.type) {
        ModuleType.diningStatus => DiningCard(
          result: widget.dining,
          category: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: _DragHandle(visible: showDragHandle),
          onShowAll: () => widget.onGoToTab(1),
        ),
        ModuleType.generalEvents => EventsCard(
          result: widget.events,
          organizerKey: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: _DragHandle(visible: showDragHandle),
          onShowAll: () => widget.onGoToTab(2),
        ),
        ModuleType.clubEvents => ScopedEventsCard(
          result: widget.events,
          organizerKey: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: _DragHandle(visible: showDragHandle),
          onShowAll: () => widget.onGoToTab(2),
        ),
        ModuleType.calendar => CalendarCard(
          result: widget.events,
          organizerKey: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: _DragHandle(visible: showDragHandle),
          onShowAll: () => widget.onGoToTab(2),
        ),
        ModuleType.visitingChefs => VisitingChefsCard(
          result: widget.chefs,
          compact: card.size == CardSize.compact,
          dragHandle: _DragHandle(visible: showDragHandle),
          onShowAll: () => widget.onGoToTab(1),
        ),
        ModuleType.mailingAddress => HousingCard(
          areas: widget.areas,
          api: widget.api,
          dragHandle: _DragHandle(visible: showDragHandle),
        ),
        ModuleType.facilityHours => FacilityHoursCard(
          result: _recreation,
          facilityName: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: _DragHandle(visible: showDragHandle),
        ),
        ModuleType.campusMap => DashboardMapCard(
          result: _campusMap,
          events: widget.events,
          dragHandle: _DragHandle(visible: showDragHandle),
        ),
      };

  /// Columns grow with width, so a wide window is not four cards huddled in
  /// the top left corner.

  /// Card height. Cards grow to use spare vertical room, which BoundedList
  /// turns into extra rows for free, but stop before they get silly.
  static const double _minCardHeight = homeMinCardHeight;
  // High enough that a single row of cards fills a large window, rather
  // than leaving a band of dead space under it.
  static const double _maxCardHeight = homeMaxCardHeight;
  static const double _cardGutter = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the viewport when there is room, without ever shrinking below
        // the height the cards were designed against.
        final available = constraints.maxHeight - _Colophon.height;
        final columns = homeGridColumns(
          constraints.maxWidth,
          available,
          _order.length,
        );
        final cells = _order.fold<int>(0, (sum, id) {
          final card = _instance(id);
          return sum + (card?.size.columns ?? 1).clamp(1, columns);
        });
        final rows = (cells / columns).ceil();
        final perRow = rows > 0 ? available / rows : _minCardHeight;
        final cardHeight = perRow
            .clamp(_minCardHeight, _maxCardHeight)
            .toDouble();

        final children = [
          for (final id in _order)
            SizedBox(
              key: ValueKey(id),
              width:
                  (constraints.maxWidth - 16) /
                  columns *
                  ((_instance(id)?.size.columns ?? 1).clamp(1, columns)),
              height:
                  (_instance(id)?.size == CardSize.compact
                      ? cardHeight * .58
                      : cardHeight) +
                  _cardGutter * 2,
              child: Padding(
                padding: const EdgeInsets.all(_cardGutter),
                child: _HoverCard(
                  builder: (hovered) => Stack(
                    children: [
                      _cardFor(id, hovered || _editing),
                      if (_editing)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            children: [
                              _InspectButton(
                                selected: _selectedId == id,
                                onTap: () => setState(() => _selectedId = id),
                              ),
                              const SizedBox(width: 6),
                              _RemoveButton(onTap: () => _removeCard(id)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ];

        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverToBoxAdapter(
                  child: ReorderableBuilder<String>(
                    // No scrollController on purpose. The inner GridView is
                    // non-scrollable and the parent CustomScrollView does the
                    // scrolling, so the package must find that itself. Passing
                    // the outer controller here is what broke dragging.
                    enableScrollingWhileDragging: false,
                    longPressDelay: const Duration(milliseconds: 180),
                    onReorder: (reorderedListFunction) {
                      setState(() => _order = reorderedListFunction(_order));
                      _persist();
                    },
                    builder: (wrapped) =>
                        Wrap(key: _gridKey, children: wrapped),
                    children: children,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _EditBar(
                  editing: _editing,
                  hidden: _hidden,
                  cards: {for (final c in _instances) c.id: c},
                  onToggle: () => setState(() => _editing = !_editing),
                  onAdd: _addCard,
                  onAddModule: _addModule,
                  selected: _selectedId == null
                      ? null
                      : _instance(_selectedId!),
                  organizers: _organizers,
                  diningCategories: _diningCategories,
                  facilities: _facilities,
                  onUpdate: _updateCard,
                  onMove: (delta) => _moveCard(_selectedId!, delta),
                ),
              ),
              const SliverToBoxAdapter(child: _Colophon()),
            ],
          ),
        );
      },
    );
  }
}

/// Edit mode: a toggle, plus the row of cards that have been removed.
class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.editing,
    required this.hidden,
    required this.cards,
    required this.onToggle,
    required this.onAdd,
    required this.onAddModule,
    required this.selected,
    required this.organizers,
    required this.diningCategories,
    required this.facilities,
    required this.onUpdate,
    required this.onMove,
  });

  final bool editing;
  final List<String> hidden;

  /// Instance id to instance, so a hidden chip can name its module rather than
  /// guessing from an id.
  final Map<String, CardInstance> cards;

  final VoidCallback onToggle;
  final ValueChanged<String> onAdd;
  final ValueChanged<ModuleType> onAddModule;
  final CardInstance? selected;
  final List<({String key, String name})> organizers;
  final List<({String key, String name})> diningCategories;
  final List<({String key, String name})> facilities;
  final ValueChanged<CardInstance> onUpdate;
  final ValueChanged<int> onMove;

  static const _available = [
    ModuleType.diningStatus,
    ModuleType.generalEvents,
    ModuleType.clubEvents,
    ModuleType.calendar,
    ModuleType.visitingChefs,
    ModuleType.mailingAddress,
    ModuleType.facilityHours,
    ModuleType.campusMap,
  ];

  Future<void> _showLibrary(BuildContext context) async {
    final picked = await showModalBottomSheet<ModuleType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            Text(
              'Add a module',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add duplicates and give each one its own scope.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final type in _available)
              ListTile(
                leading: Icon(moduleIcons[type]),
                title: Text(moduleLabels[type]!),
                subtitle: Text(switch (type) {
                  ModuleType.clubEvents => 'Follow one organization',
                  ModuleType.calendar => 'Browse the next seven days',
                  ModuleType.facilityHours => 'See today’s recreation hours',
                  ModuleType.campusMap => 'Keep campus wayfinding on Today',
                  _ => 'Add another ${moduleLabels[type]!.toLowerCase()} card',
                }),
                trailing: const Icon(Icons.add_rounded),
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onAddModule(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                elevation: 0,
                color: editing ? scheme.primary : scheme.surfaceContainerHigh,
                shape: Shapes.pill,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          editing ? Icons.check_rounded : Icons.tune_rounded,
                          size: 18,
                          color: editing
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          editing ? 'Done' : 'Customize',
                          style: text.bodyMedium?.copyWith(
                            color: editing
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (editing) ...[
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _showLibrary(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add module'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Drag to reorder, or tune a card',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ],
          ),
          if (editing && selected != null) ...[
            const SizedBox(height: 14),
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: Shapes.card,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          moduleIcons[selected!.type],
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            moduleLabels[selected!.type]!,
                            style: text.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Move earlier',
                          onPressed: () => onMove(-1),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        IconButton(
                          tooltip: 'Move later',
                          onPressed: () => onMove(1),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ],
                    ),
                    Text('SIZE', style: text.labelSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 7,
                      children: [
                        for (final size in supportedSizes[selected!.type]!)
                          ChoiceChip(
                            label: Text(switch (size) {
                              CardSize.compact => 'Compact',
                              CardSize.standard => 'Standard',
                              CardSize.wide => 'Wide',
                            }),
                            selected: selected!.size == size,
                            onSelected: (_) =>
                                onUpdate(selected!.copyWith(size: size)),
                          ),
                      ],
                    ),
                    if (selected!.type == ModuleType.diningStatus) ...[
                      const SizedBox(height: 12),
                      Text('DINING CATEGORY', style: text.labelSmall),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            diningCategories.any(
                              (item) => item.key == selected!.scope,
                            )
                            ? selected!.scope
                            : '',
                        decoration: const InputDecoration(
                          hintText: 'All dining',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All dining'),
                          ),
                          for (final category in diningCategories)
                            DropdownMenuItem(
                              value: category.key,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) => onUpdate(
                          value == null || value.isEmpty
                              ? selected!.copyWith(clearScope: true)
                              : selected!.copyWith(scope: value),
                        ),
                      ),
                    ],
                    if (selected!.type == ModuleType.generalEvents ||
                        selected!.type == ModuleType.clubEvents ||
                        selected!.type == ModuleType.calendar) ...[
                      const SizedBox(height: 12),
                      Text('ORGANIZATION', style: text.labelSmall),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            organizers.any((o) => o.key == selected!.scope)
                            ? selected!.scope
                            : '',
                        decoration: const InputDecoration(
                          hintText: 'All organizations',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All organizations'),
                          ),
                          for (final organizer in organizers)
                            DropdownMenuItem(
                              value: organizer.key,
                              child: Text(organizer.name),
                            ),
                        ],
                        onChanged: (value) => onUpdate(
                          value == null || value.isEmpty
                              ? selected!.copyWith(clearScope: true)
                              : selected!.copyWith(scope: value),
                        ),
                      ),
                    ],
                    if (selected!.type == ModuleType.facilityHours) ...[
                      const SizedBox(height: 12),
                      Text('FACILITY', style: text.labelSmall),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            facilities.any(
                              (item) => item.key == selected!.scope,
                            )
                            ? selected!.scope
                            : '',
                        decoration: const InputDecoration(
                          hintText: 'All facilities',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All facilities'),
                          ),
                          for (final facility in facilities)
                            DropdownMenuItem(
                              value: facility.key,
                              child: Text(facility.name),
                            ),
                        ],
                        onChanged: (value) => onUpdate(
                          value == null || value.isEmpty
                              ? selected!.copyWith(clearScope: true)
                              : selected!.copyWith(scope: value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (editing && hidden.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('ADD A CARD', style: text.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in hidden)
                  Material(
                    elevation: 0,
                    color: scheme.surfaceContainerHigh,
                    shape: Shapes.pill,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onAdd(id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 17,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 7),
                            Icon(
                              moduleIcons[cards[id]?.type] ??
                                  Icons.widgets_rounded,
                              size: 17,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              moduleLabels[cards[id]?.type] ?? 'Card',
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (editing && hidden.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Every card is on screen.', style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: scheme.errorContainer,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _InspectButton extends StatelessWidget {
  const _InspectButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.tune_rounded, size: 18, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// Reveals the drag handle on hover, so it is not permanent visual noise.
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mouseConnected =
        RendererBinding.instance.mouseTracker.mouseIsConnected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered || !mouseConnected),
    );
  }
}

class _Colophon extends StatelessWidget {
  const _Colophon();

  static const double height = 64;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 14, 26, 26),
    child: Text(
      AppConfig.disclaimer,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      // The space is always reserved, so revealing the handle never shifts
      // the title next to it.
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Icon(
          Icons.drag_indicator_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
