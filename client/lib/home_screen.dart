/// Today tab: the drag and drop reorderable card grid.
///
/// Card order persists locally. Every card paints from cache immediately, so
/// there is no cold start spinner once the app has run at least once.
library;

import 'package:flutter/material.dart';
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

  Widget _cardFor(String id) => switch (id) {
        'dining' => DiningCard(
            result: widget.dining,
            dragHandle: const _DragHandle(),
            onShowAll: () => widget.onGoToTab(1),
          ),
        'events' => EventsCard(
            result: widget.events,
            dragHandle: const _DragHandle(),
            onShowAll: () => widget.onGoToTab(2),
          ),
        'chefs' => VisitingChefsCard(
            result: widget.chefs,
            dragHandle: const _DragHandle(),
            onShowAll: () => widget.onGoToTab(1),
          ),
        'housing' => HousingCard(
            areas: widget.areas,
            api: widget.api,
            dragHandle: const _DragHandle(),
          ),
        _ => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 700 ? 1 : (width < 1240 ? 2 : 3);

    final children = [
      for (final id in _order)
        Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.all(6),
          child: _cardFor(id),
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
                    mainAxisExtent: 344,
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
  }
}

class _Colophon extends StatelessWidget {
  const _Colophon();

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
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8, top: 3),
        child: Icon(
          Icons.drag_indicator_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}
