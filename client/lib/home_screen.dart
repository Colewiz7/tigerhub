/// Today tab: the drag and drop reorderable card grid.
///
/// Card order persists locally. Every card paints from cache immediately, so
/// there is no cold start spinner once the app has run at least once.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import 'cards/dining_card.dart';
import 'cards/events_card.dart';
import 'cards/housing_card.dart';
import 'cards/visiting_chefs_card.dart';
import 'config.dart';
import 'models/api_models.dart';
import 'services/api.dart';
import 'services/cache.dart';

const List<String> _defaultOrder = ['dining', 'events', 'chefs', 'housing'];

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

  @override
  void initState() {
    super.initState();
    _restoreOrder();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreOrder() async {
    final saved = await ResponseCache.instance.readOrder('cards');
    if (!mounted || saved.isEmpty) return;
    // Tolerate a stored order from an older build that added or removed cards.
    final merged = [
      ...saved.where(_defaultOrder.contains),
      ..._defaultOrder.where((id) => !saved.contains(id)),
    ];
    setState(() => _order = merged);
  }

  Widget _cardFor(String id, bool showDragHandle) => switch (id) {
    'dining' => DiningCard(
      result: widget.dining,
      dragHandle: _DragHandle(visible: showDragHandle),
      onShowAll: () => widget.onGoToTab(1),
    ),
    'events' => EventsCard(
      result: widget.events,
      dragHandle: _DragHandle(visible: showDragHandle),
      onShowAll: () => widget.onGoToTab(2),
    ),
    'chefs' => VisitingChefsCard(
      result: widget.chefs,
      dragHandle: _DragHandle(visible: showDragHandle),
      onShowAll: () => widget.onGoToTab(1),
    ),
    'housing' => HousingCard(
      areas: widget.areas,
      api: widget.api,
      dragHandle: _DragHandle(visible: showDragHandle),
    ),
    _ => const SizedBox.shrink(),
  };

  /// Columns grow with width, so a wide window is not four cards huddled in
  /// the top left corner.
  static int _columnsFor(double width) {
    if (width < 820) return 1;
    if (width < 1300) return 2;
    if (width < 1850) return 3;
    return 4;
  }

  /// Card height. Cards grow to use spare vertical room, which BoundedList
  /// turns into extra rows for free, but stop before they get silly.
  static const double _minCardHeight = 480;
  // High enough that a single row of cards fills a large window, rather
  // than leaving a band of dead space under it.
  static const double _maxCardHeight = 860;
  static const double _cardGutter = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        final rows = (_order.length / columns).ceil();

        // Fill the viewport when there is room, without ever shrinking below
        // the height the cards were designed against.
        final available = constraints.maxHeight - _Colophon.height;
        final perRow = rows > 0 ? available / rows : _minCardHeight;
        final cardHeight = perRow
            .clamp(_minCardHeight, _maxCardHeight)
            .toDouble();

        final children = [
          for (final id in _order)
            Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.all(_cardGutter),
              child: _HoverCard(builder: (hovered) => _cardFor(id, hovered)),
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
                    scrollController: _scrollController,
                    enableScrollingWhileDragging: false,
                    onReorder: (reorderedListFunction) {
                      setState(() => _order = reorderedListFunction(_order));
                      ResponseCache.instance.writeOrder('cards', _order);
                    },
                    builder: (wrapped) => GridView(
                      key: _gridKey,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        // The card height plus the gutter on each side.
                        mainAxisExtent: cardHeight + _cardGutter * 2,
                      ),
                      children: wrapped,
                    ),
                    children: children,
                  ),
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
