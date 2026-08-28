/// Home screen: a masthead and a drag and drop reorderable grid of cards.
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
import 'theme/app_theme.dart';

const List<String> _defaultOrder = ['dining', 'events', 'chefs', 'housing'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();

  List<String> _order = _defaultOrder;

  Result<Collection<DiningLocation>> _dining =
      const Result(value: null, state: DataState.priming);
  Result<Collection<CampusEvent>> _events =
      const Result(value: null, state: DataState.priming);
  Result<Collection<MenuItem>> _chefs =
      const Result(value: null, state: DataState.priming);
  Result<Collection<HousingArea>> _areas =
      const Result(value: null, state: DataState.priming);

  @override
  void initState() {
    super.initState();
    _restoreOrder();
    _refresh();
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

  Future<void> _refresh() async {
    widget.api.dining().listen((r) {
      if (mounted) setState(() => _dining = r);
    });
    widget.api.events().listen((r) {
      if (mounted) setState(() => _events = r);
    });
    widget.api.visitingChefs().listen((r) {
      if (mounted) setState(() => _chefs = r);
    });
    widget.api.housingAreas().listen((r) {
      if (mounted) setState(() => _areas = r);
    });
  }

  /// Placeholder for the detail view. The "+N more" rows are already wired to
  /// this so the tap target exists before the screen does.
  void _openDetail(String cardId) {
    // Intentionally does nothing yet.
  }

  Widget _cardFor(String id) => switch (id) {
        'dining' => DiningCard(
            result: _dining,
            dragHandle: const _DragHandle(),
            onShowAll: () => _openDetail('dining'),
          ),
        'events' => EventsCard(
            result: _events,
            dragHandle: const _DragHandle(),
            onShowAll: () => _openDetail('events'),
          ),
        'chefs' => VisitingChefsCard(
            result: _chefs,
            dragHandle: const _DragHandle(),
            onShowAll: () => _openDetail('chefs'),
          ),
        'housing' => HousingCard(
            areas: _areas,
            api: widget.api,
            dragHandle: const _DragHandle(),
          ),
        _ => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // One column on a phone, two on a tablet or desktop window, three when wide.
    final columns = width < 700 ? 1 : (width < 1200 ? 2 : 3);

    final children = [
      for (final id in _order)
        Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.all(8),
          child: _cardFor(id),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: _Masthead()),
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
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 340,
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
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final rule = AppTheme.ruleOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: rule),
          const SizedBox(height: 10),
          Center(
            child: Text(
              AppConfig.appName.toUpperCase(),
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: rule),
        ],
      ),
    );
  }
}

class _Colophon extends StatelessWidget {
  const _Colophon();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
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
        padding: const EdgeInsets.only(left: 8, top: 2),
        child: Icon(
          Icons.drag_indicator,
          size: 16,
          color: AppTheme.mutedOf(context),
        ),
      );
}
