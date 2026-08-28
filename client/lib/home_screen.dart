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
import 'theme/tokens.dart';

const List<String> _defaultOrder = ['dining', 'events', 'chefs', 'housing'];

const Map<String, ({String label, IconData icon})> _cardCatalogue = {
  'dining': (label: 'Dining', icon: Icons.restaurant_rounded),
  'events': (label: 'Events', icon: Icons.event_note_rounded),
  'chefs': (label: 'Visiting Chefs', icon: Icons.restaurant_menu_rounded),
  'housing': (label: 'Mailing Address', icon: Icons.markunread_mailbox_rounded),
};

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
    final hidden = await ResponseCache.instance.readOrder('cards_hidden');
    if (!mounted) return;

    final known = _cardCatalogue.keys.toList();
    final validHidden = hidden.where(known.contains).toList();

    // Tolerate a stored order from an older build that added or removed cards.
    final merged = saved.isEmpty
        ? known
        : [
            ...saved.where(known.contains),
            ...known.where((id) => !saved.contains(id) && !validHidden.contains(id)),
          ];

    setState(() {
      _hidden = validHidden;
      _order = merged.where((id) => !validHidden.contains(id)).toList();
    });
  }

  Future<void> _persist() async {
    await ResponseCache.instance.writeOrder('cards', _order);
    await ResponseCache.instance.writeOrder('cards_hidden', _hidden);
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
  static const double _minCardHeight = 560;
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
              child: _HoverCard(
                builder: (hovered) => Stack(
                  children: [
                    // Handles also stay visible while editing, so it is
                    // obvious which cards can be moved.
                    _cardFor(id, hovered || _editing),
                    if (_editing)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _RemoveButton(onTap: () => _removeCard(id)),
                      ),
                  ],
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
              SliverToBoxAdapter(
                child: _EditBar(
                  editing: _editing,
                  hidden: _hidden,
                  onToggle: () => setState(() => _editing = !_editing),
                  onAdd: _addCard,
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
    required this.onToggle,
    required this.onAdd,
  });

  final bool editing;
  final List<String> hidden;
  final VoidCallback onToggle;
  final ValueChanged<String> onAdd;

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
                color: editing
                    ? scheme.primary
                    : scheme.surfaceContainerHigh,
                shape: Shapes.pill,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onToggle,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          editing ? Icons.check_rounded : Icons.tune_rounded,
                          size: 18,
                          color: editing ? scheme.onPrimary : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          editing ? 'Done' : 'Customize',
                          style: text.bodyMedium?.copyWith(
                            color:
                                editing ? scheme.onPrimary : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (editing) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Drag a card to reorder it',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ],
          ),
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
                            horizontal: 15, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                size: 17, color: scheme.primary),
                            const SizedBox(width: 7),
                            Icon(_cardCatalogue[id]!.icon,
                                size: 17, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 7),
                            Text(_cardCatalogue[id]!.label,
                                style: text.bodyMedium),
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
          child: Icon(Icons.close_rounded,
              size: 18, color: scheme.onErrorContainer),
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
