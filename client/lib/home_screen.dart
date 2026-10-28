/// Today tab: the drag and drop reorderable card grid.
///
/// Card order persists locally. Every card paints from cache immediately, so
/// there is no cold start spinner once the app has run at least once.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import 'cards/dining_card.dart';
import 'cards/dashboard_event_cards.dart';
import 'cards/dashboard_campus_cards.dart';
import 'cards/calendar_card.dart';
import 'cards/event_row.dart' show eventEnd;
import 'cards/events_card.dart';
import 'cards/housing_card.dart';
import 'cards/visiting_chefs_card.dart';
import 'cards/academic_dates_card.dart';
import 'cards/shuttles_card.dart';
import 'cards/package_pickup_card.dart';
import 'data/campus_time.dart';
import 'models/api_models.dart';
import 'motion/reduce_motion.dart';
import 'services/api.dart';
import 'services/dashboard.dart';
import 'services/smart_order.dart';
import 'services/event_filter.dart';
import 'services/preferences.dart';
import 'theme/tokens.dart';
import 'widgets/app_icon.dart';
import 'widgets/card_shell.dart' show editControlsWidth;
import 'widgets/compact_card.dart' show CompactPair;
import 'widgets/context_actions.dart' show ContextActionsScope;
import 'widgets/tab_bar.dart';
import 'widgets/today_header.dart';
import 'widgets/touch_target.dart';

/// The icon each module type shows in the card library and the hidden chips.
/// The name comes from `moduleLabels` beside the type itself, so the library
/// and the renderer cannot drift apart.
const Map<ModuleType, AppIconKind> moduleIcons = {
  ModuleType.diningStatus: AppIconKind.dining,
  ModuleType.generalEvents: AppIconKind.events,
  ModuleType.clubEvents: AppIconKind.groups,
  ModuleType.calendar: AppIconKind.calendar,
  ModuleType.visitingChefs: AppIconKind.menu,
  ModuleType.mailingAddress: AppIconKind.mailbox,
  ModuleType.facilityHours: AppIconKind.gym,
  ModuleType.campusMap: AppIconKind.map,
  ModuleType.academicDates: AppIconKind.academicDates,
  ModuleType.shuttles: AppIconKind.shuttle,
  ModuleType.packagePickup: AppIconKind.mail,
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

/// Types whose compact size on a phone is a [CompactCard].
const Set<ModuleType> compactBodyTypes = {
  ModuleType.visitingChefs,
  ModuleType.facilityHours,
  ModuleType.shuttles,
  ModuleType.packagePickup,
};

/// Two up only while a half card still holds its value.
bool phoneTwoUp({required double width, required double textScale}) => width >= 360 && textScale <= 1.35;

/// Positions that share a row on a phone: two compact cards next to each
/// other in reading order. A compact card on its own stays full width, and
/// the saved order never changes.
Set<int> phonePairs(List<CardInstance?> cards) {
  bool half(int i) {
    final card = cards[i];
    return card != null && card.size == CardSize.compact && compactBodyTypes.contains(card.type);
  }

  final paired = <int>{};
  for (var i = 0; i + 1 < cards.length; i++) {
    if (paired.contains(i)) continue;
    if (half(i) && half(i + 1)) paired.addAll([i, i + 1]);
  }
  return paired;
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
    this.onOpenSettings,
  });

  final ApiClient api;
  final Result<Collection<DiningLocation>> dining;
  final Result<Collection<CampusEvent>> events;
  final Result<Collection<MenuItem>> chefs;
  final Result<Collection<HousingArea>> areas;
  final Future<void> Function() onRefresh;

  /// The "+N more" footers land on the matching tab.
  final ValueChanged<int> onGoToTab;

  /// The shell's gear. When set, Today heads itself with the mark, the date
  /// and the gear.
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();
  final _headerKey = GlobalKey();

  /// The large date has scrolled under the top edge.
  bool _collapsed = false;

  void _onScrolled() {
    final header = _headerKey.currentContext?.size?.height;
    final collapsed = header != null && _scrollController.hasClients && _scrollController.offset >= header - 8;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  List<String> _order = [for (final card in defaultDashboard) card.id];

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
  Result<Collection<PostOffice>> _offices = const Result(
    value: null,
    state: DataState.priming,
  );
  StreamSubscription<Result<Collection<PostOffice>>>? _officesSub;

  // ended events leave without new data
  Timer? _minute;

  void _tickMinute() {
    final now = CampusTime.nowUtc();
    final wait = Duration(seconds: 60 - now.second, milliseconds: -now.millisecond);
    _minute = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _tickMinute();
    });
  }

  // smart order and filters move cards
  void _onPreferences() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrolled);
    Preferences.instance.addListener(_onPreferences);
    _tickMinute();
    _restoreOrder();
    _recreationSub = widget.api.recreation().listen((result) {
      if (mounted) setState(() => _recreation = result);
    });
    _mapSub = widget.api.campusMap().listen((result) {
      if (mounted) setState(() => _campusMap = result);
    });
    _officesSub = widget.api.postOffices().listen((result) {
      if (mounted) setState(() => _offices = result);
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScrolled)
      ..dispose();
    Preferences.instance.removeListener(_onPreferences);
    _minute?.cancel();
    _recreationSub?.cancel();
    _mapSub?.cancel();
    _officesSub?.cancel();
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
    final removed = _instance(id);
    setState(() {
      _order = _order.where((c) => c != id).toList();
      _hidden = [..._hidden, id];
      if (_selectedId == id) _selectedId = null;
    });
    _announce('${moduleLabels[removed?.type] ?? 'Card'} removed');
    _persist();
  }

  void _addCard(String id) {
    final added = _instance(id);
    setState(() {
      _hidden = _hidden.where((c) => c != id).toList();
      _order = [..._order, id];
    });
    _announce('${moduleLabels[added?.type] ?? 'Card'} added');
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
      // The calendar's value is the seven-day shape, which needs the two
      // column footprint. Other modules start at their least expensive size.
      size: defaultSizeFor(type),
      // a facility card starts on the pool
      scope: type == ModuleType.facilityHours ? defaultFacilityName(_recreation.value?.data ?? const []) : null,
    );
    setState(() {
      _instances = [..._instances, card];
      _order = [..._order, card.id];
      _selectedId = card.id;
    });
    _announce('${moduleLabels[type]} added, position ${_order.length}');
    await _persist();
  }

  Future<void> _updateCard(CardInstance updated) async {
    final previous = _instance(updated.id);
    String? spoken;
    setState(() {
      _instances = [
        for (final card in _instances)
          if (card.id == updated.id) updated else card,
      ];
      if (previous?.size != updated.size) {
        spoken = '${moduleLabels[updated.type]} resized to ${updated.size.id}';
      } else if (previous?.scope != updated.scope) {
        spoken = '${moduleLabels[updated.type]} scope updated';
      }
    });
    if (spoken != null) _announce(spoken!);
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
    _announce(
      '${moduleLabels[_instance(id)?.type] ?? 'Card'} moved to position ${to + 1}',
    );
    _persist();
  }

  /// Speaks [message] to screen readers. A zero size live region is dropped
  /// from the semantics tree, so every announcement goes through here.
  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
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

  // today shows what is still ahead, ended events drop off
  Result<Collection<CampusEvent>> get _upcomingEvents => _upcoming(false);

  // saved mutes and hide words apply too
  Result<Collection<CampusEvent>> get _filteredUpcomingEvents =>
      _upcoming(true);

  /// What Today shows first. The saved order, unless smart order is on and
  /// nothing is being edited.
  List<String> get _displayOrder {
    if (_editing || !Preferences.instance.todaySmartOrder) return _order;
    final now = CampusTime.nowUtc();
    final wall = CampusTime.fieldsOf(now);
    final cards = [
      for (final id in _order) ?_instance(id),
    ];
    final ordered = smartOrder(
      cards,
      wallMinute: wall.hour * 60 + wall.minute,
      eventSoon: eventWithinHour(_filteredUpcomingEvents.value?.data ?? const [], now),
    );
    return [for (final card in ordered) card.id];
  }

  // boost words only break ties in up next
  Set<String> get _boostedUids {
    final data = widget.events.value?.data;
    if (data == null) return const {};
    return {
      for (final group in filterEvents(data, Preferences.instance).groups)
        for (final item in group.visible)
          if (item.boosted) item.event.uid,
    };
  }

  Result<Collection<CampusEvent>> _upcoming(bool applyFilters) {
    final result = widget.events;
    final value = result.value;
    if (value == null) return result;
    final now = CampusTime.nowUtc();
    final visible = applyFilters
        ? {
            for (final group
                in filterEvents(value.data, Preferences.instance).groups)
              for (final item in group.visible) item.event,
          }
        : null;
    return Result(
      value: Collection(
        data: [
          for (final event in value.data)
            if (eventEnd(event).isAfter(now) &&
                (visible == null || visible.contains(event)))
              event,
        ],
        stale: value.stale,
        lastUpdated: value.lastUpdated,
        dropped: value.dropped,
        availability: value.availability,
      ),
      state: result.state,
      fetchedAt: result.fetchedAt,
      error: result.error,
      dropped: result.dropped,
    );
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

  Widget _cardFor(String id) {
    final card = _instance(id);
    if (card == null) return const SizedBox.shrink();
    // The handle, Inspect and Remove sit in the card's own header, so they
    // can never cover each other or the title. None of them exist outside
    // edit mode.
    final controls = _editing
        ? EditControls(
            selected: _selectedId == id,
            onInspect: () => setState(() => _selectedId = id),
            onRemove: () => _removeCard(id),
          )
        : null;
    return _moduleFor(card, controls);
  }

  /// One module type to one widget. This is the seam the spec's later stages
  /// hang off: adding a card type is a case here plus an entry in the library,
  /// not a change to how the grid works.
  Widget _moduleFor(CardInstance card, Widget? controls) =>
      switch (card.type) {
        ModuleType.diningStatus => DiningCard(
          result: widget.dining,
          category: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(1),
        ),
        ModuleType.generalEvents => ListenableBuilder(
          listenable: Preferences.instance,
          builder: (context, _) => EventsCard(
            result: _filteredUpcomingEvents,
            boosted: _boostedUids,
            organizerKey: card.scope,
            compact: card.size == CardSize.compact,
            dragHandle: controls,
            onShowAll: () => widget.onGoToTab(2),
          ),
        ),
        ModuleType.clubEvents => ScopedEventsCard(
          result: _upcomingEvents,
          organizerKey: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(2),
        ),
        ModuleType.calendar => CalendarCard(
          result: _upcomingEvents,
          organizerKey: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(2),
        ),
        ModuleType.visitingChefs => VisitingChefsCard(
          result: widget.chefs,
          compact: card.size == CardSize.compact,
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(1),
        ),
        ModuleType.mailingAddress => HousingCard(
          areas: widget.areas,
          api: widget.api,
          dragHandle: controls,
        ),
        ModuleType.facilityHours => FacilityHoursCard(
          result: _recreation,
          facilityName: card.scope,
          compact: card.size == CardSize.compact,
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(4),
        ),
        ModuleType.campusMap => DashboardMapCard(
          result: _campusMap,
          events: widget.events,
          dragHandle: controls,
        ),
        ModuleType.academicDates => AcademicDatesCard(
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(4),
        ),
        ModuleType.shuttles => ShuttlesCard(
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(4),
        ),
        ModuleType.packagePickup => PackagePickupCard(
          areas: widget.areas,
          offices: _offices,
          dragHandle: controls,
          onShowAll: () => widget.onGoToTab(4),
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

  // room kept for edit today, wide cells unchanged
  static const double _pageEndHeight = 64;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the viewport when there is room, without ever shrinking below
        // the height the cards were designed against.
        final available = constraints.maxHeight - _pageEndHeight;
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

        // Phone tokens: cards 16 from the window edge and 10 apart, so each
        // cell carries 5 of padding and the page inset makes up the rest.
        final phone = Insets.phone(context);
        final gutter = phone ? Insets.phoneCardGap / 2 : _cardGutter;
        final sideInset = phone ? Insets.phoneMargin - gutter : 8.0;
        final twoUp = phone && phoneTwoUp(width: constraints.maxWidth, textScale: MediaQuery.textScalerOf(context).scale(1));
        final shown = _displayOrder;
        final pairs = twoUp ? phonePairs([for (final id in shown) _instance(id)]) : const <int>{};

        final children = [
          for (var index = 0; index < shown.length; index++)
            Semantics(
              key: ValueKey(shown[index]),
              container: true,
              sortKey: OrdinalSortKey(index.toDouble()),
              customSemanticsActions: {
                if (_editing && index > 0)
                  const CustomSemanticsAction(label: 'Move up'): () =>
                      _moveCard(shown[index], -1),
                if (_editing && index < shown.length - 1)
                  const CustomSemanticsAction(label: 'Move down'): () =>
                      _moveCard(shown[index], 1),
              },
              label: dashboardCardSemanticsLabel(
                _instance(shown[index]),
                index + 1,
                shown.length,
              ),
              child: SizedBox(
                width: pairs.contains(index)
                    ? (constraints.maxWidth - sideInset * 2) / 2
                    : (constraints.maxWidth - sideInset * 2) /
                          columns *
                          ((_instance(shown[index])?.size.columns ?? 1).clamp(
                            1,
                            columns,
                          )),
                // Phones size a card to its content, so there is no cell
                // height. Wider windows divide the viewport into cells.
                height: phone
                    ? null
                    : (_instance(shown[index])?.size == CardSize.compact
                              ? cardHeight * .58
                              : cardHeight) +
                          gutter * 2,
                child: Padding(
                  padding: EdgeInsets.all(gutter),
                  // A Stack, as before the header controls moved into the
                  // card: it hands the card loose constraints, so a card
                  // keeps its natural height inside its cell.
                  child: Stack(
                    children: [
                      pairs.contains(index)
                          ? CompactPair(child: _cardFor(shown[index]))
                          : _cardFor(shown[index]),
                    ],
                  ),
                ),
              ),
            ),
        ];

        final openSettings = widget.onOpenSettings;
        final date = CampusTime.wallDate();

        // Long-press is a drag in edit mode, so row menus are off there.
        final page = ContextActionsScope(
          enabled: !_editing,
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              controller: _scrollController,
              slivers: [
                if (openSettings != null)
                  SliverToBoxAdapter(
                    child: TodayHeader(key: _headerKey, date: date, onOpenSettings: openSettings),
                  ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: sideInset),
                  sliver: SliverToBoxAdapter(
                    child: ReorderableBuilder<String>(
                      // No scrollController on purpose. The inner GridView is
                      // non-scrollable and the parent CustomScrollView does the
                      // scrolling, so the package must find that itself. Passing
                      // the outer controller here is what broke dragging.
                      enableScrollingWhileDragging: false,
                      enableDraggable: _editing,
                      longPressDelay: const Duration(milliseconds: 180),
                      onReorder: (reorderedListFunction) {
                        setState(() {
                          _order = reorderedListFunction(_order);
                        });
                        _announce('Dashboard order updated');
                        HapticFeedback.lightImpact();
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
                    onToggle: () {
                      setState(() {
                        _editing = !_editing;
                        if (!_editing) _selectedId = null;
                      });
                      _announce(
                        _editing
                            ? 'Editing Today. Select a card to edit it.'
                            : 'Done editing Today',
                      );
                    },
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
                SliverToBoxAdapter(child: SizedBox(height: TabBarInset.of(context))),
              ],
            ),
          ),
        );
        if (openSettings == null) return page;
        return Stack(
          children: [
            page,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 160),
                child: _collapsed
                    ? TodayCollapsedBar(date: date, onOpenSettings: openSettings)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
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
    ModuleType.academicDates,
    ModuleType.shuttles,
    ModuleType.packagePickup,
  ];

  Future<void> _showLibrary(BuildContext context) async {
    final picked = await showModalBottomSheet<ModuleType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                leading: Icon(moduleIcons[type]!.of(context)),
                title: Text(moduleLabels[type]!),
                subtitle: Text(switch (type) {
                  ModuleType.clubEvents => 'Follow one organization',
                  ModuleType.calendar => 'Browse the next seven days',
                  ModuleType.facilityHours => 'See today’s recreation hours',
                  ModuleType.campusMap => 'Keep campus wayfinding on Today',
                  ModuleType.academicDates => 'Keep the next deadline visible',
                  ModuleType.shuttles => 'Routes from home and until when',
                  ModuleType.packagePickup => 'Your post office counter hours',
                  _ => 'Add another ${moduleLabels[type]!.toLowerCase()} card',
                }),
                trailing: Icon(AppIconKind.add.of(context)),
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

    // the end of the page, one quiet button
    if (!editing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
        child: Center(
          child: _BarPill(
            onTap: onToggle,
            icon: AppIconKind.tune,
            label: 'Edit Today',
            background: Colors.transparent,
            outline: scheme.outlineVariant,
            iconColor: scheme.onSurfaceVariant,
            labelColor: scheme.onSurface,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A Wrap, so at large text the hint drops to its own line rather
          // than pushing the buttons off the edge.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _BarPill(
                onTap: onToggle,
                icon: AppIconKind.check,
                label: 'Done',
                background: scheme.primary,
                iconColor: scheme.onPrimary,
                labelColor: scheme.onPrimary,
              ),
              if (editing) ...[
                _BarPill(
                  onTap: () => _showLibrary(context),
                  icon: AppIconKind.add,
                  label: 'Add module',
                  background: scheme.primaryContainer,
                  iconColor: scheme.onPrimaryContainer,
                  labelColor: scheme.onPrimaryContainer,
                ),
                Text('Drag to reorder, or tune a card', style: text.bodySmall),
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
                          moduleIcons[selected!.type]!.of(context),
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
                          tooltip: 'Move up',
                          onPressed: () => onMove(-1),
                          icon: Icon(AppIconKind.back.of(context)),
                        ),
                        IconButton(
                          tooltip: 'Move down',
                          onPressed: () => onMove(1),
                          icon: Icon(AppIconKind.forward.of(context)),
                        ),
                      ],
                    ),
                    Text('Size', style: text.labelSmall),
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
                      Text('Dining category', style: text.labelSmall),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        icon: Icon(AppIconKind.dropdown.of(context)),
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
                      Text('Organization', style: text.labelSmall),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        icon: Icon(AppIconKind.dropdown.of(context)),
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
                      Text('Facility', style: text.labelSmall),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        icon: Icon(AppIconKind.dropdown.of(context)),
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
            Text('Add a card', style: text.labelSmall),
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
                              AppIconKind.add.of(context),
                              size: 17,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 7),
                            Icon(
                              (moduleIcons[cards[id]?.type] ?? AppIconKind.widgets).of(context),
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

/// A pill in the edit bar. Every pill there is this widget, so they share a
/// height at any text size, and the icon scales with the text beside it.
class _BarPill extends StatelessWidget {
  const _BarPill({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.background,
    required this.iconColor,
    required this.labelColor,
    this.outline,
  });

  final VoidCallback onTap;
  final AppIconKind icon;
  final String label;
  final Color background;
  final Color iconColor;
  final Color labelColor;

  /// A hairline edge, for a pill with no fill.
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    // The pill is the visual; taps answer across a 48 tall region around it.
    return TouchTarget(onTap: onTap, child: _visual(context));
  }

  Widget _visual(BuildContext context) {
    return Material(
      elevation: 0,
      color: background,
      shape: outline == null ? Shapes.pill : StadiumBorder(side: BorderSide(color: outline!)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            // The spec's pill-x of 13, which is what lets "Edit Today" fit a
            // 390 wide phone at 2x text.
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon.of(context), size: 18, color: iconColor, applyTextScaling: true),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: labelColor),
                ),
              ],
            ),
          ),
        ),
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
    return Tooltip(
      message: 'Remove card from Today',
      child: Semantics(
        button: true,
        label: 'Remove card from Today',
        child: Material(
          elevation: 0,
          color: scheme.errorContainer,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(
                AppIconKind.close.of(context),
                size: 18,
                color: scheme.onErrorContainer,
              ),
            ),
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
    return Tooltip(
      message: selected ? 'Close card options' : 'Customize card',
      child: Semantics(
        button: true,
        toggled: selected,
        label: selected ? 'Close card options' : 'Customize card',
        child: Material(
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
              child: Icon(
                AppIconKind.tune.of(context),
                size: 18,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The edit mode controls in a card header: drag handle, Inspect, Remove.
///
/// One row, so the three can never overlap each other at any width or text
/// scale. CardShell gives the row its own space beside the title.
class EditControls extends StatelessWidget {
  const EditControls({
    super.key,
    required this.selected,
    required this.onInspect,
    required this.onRemove,
  });

  final bool selected;
  final VoidCallback onInspect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: editControlsWidth,
    child: Row(
      children: [
        _DragHandle(onActivate: onInspect),
        const SizedBox(width: 6),
        _InspectButton(selected: selected, onTap: onInspect),
        const SizedBox(width: 6),
        _RemoveButton(onTap: onRemove),
      ],
    ),
  );
}

/// Only built in edit mode, where it fades in. Tab reaches it and a focus
/// ring shows for keyboard focus. Enter or Space opens the card's options,
/// which carry the Move up and Move down buttons, so the keyboard has a way
/// to reorder as well as a way to land on the handle.
class _DragHandle extends StatefulWidget {
  const _DragHandle({required this.onActivate});

  static const double size = 32;

  final VoidCallback onActivate;

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  bool _shown = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Reorder card',
      hint: 'Opens card options with Move up and Move down',
      excludeSemantics: true,
      onTap: widget.onActivate,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate();
              return null;
            },
          ),
        },
        child: SizedBox(
          width: _DragHandle.size,
          height: _DragHandle.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: _shown ? 1 : 0,
                duration: reduceMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 130),
                curve: Curves.easeOutCubic,
                child: Icon(
                  AppIconKind.dragHandle.of(context),
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              // Spec focus ring: 2px primary, 2px offset, element radius + 2.
              if (_focused)
                Positioned(
                  key: const ValueKey('drag-handle-focus-ring'),
                  left: -4,
                  top: -4,
                  right: -4,
                  bottom: -4,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
