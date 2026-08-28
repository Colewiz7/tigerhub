/// App shell: the tab bar plus the four areas behind it.
///
/// Tabs are per area, and the home tab keeps the reorderable card grid. The
/// "+N more" footers navigate here, which is what makes them real rather than
/// decorative.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'home_screen.dart';
import 'models/api_models.dart';
import 'screens/campus_screen.dart';
import 'screens/dining_screen.dart';
import 'screens/events_screen.dart';
import 'services/api.dart';
import 'theme/dynamic_theme.dart';
import 'widgets/tab_bar.dart';

const List<TabSpec> _tabs = [
  TabSpec(icon: Icons.grid_view_rounded, label: 'TODAY'),
  TabSpec(icon: Icons.restaurant_rounded, label: 'DINING'),
  TabSpec(icon: Icons.event_note_rounded, label: 'EVENTS'),
  TabSpec(icon: Icons.location_city_rounded, label: 'CAMPUS'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api, required this.scheme});

  final ApiClient api;
  final SchemeController scheme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

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
    _refresh();
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

  void _go(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      // Digit keys jump between tabs. Standard on a desktop app, and it also
      // makes the UI drivable for screenshots.
      body: CallbackShortcuts(
        bindings: {
          for (var i = 0; i < _tabs.length; i++)
            SingleActivator(_digits[i]): () => _go(i),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
        child: Column(
          children: [
            _Masthead(scheme: widget.scheme),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  HomeScreen(
                    api: widget.api,
                    dining: _dining,
                    events: _events,
                    chefs: _chefs,
                    areas: _areas,
                    onRefresh: _refresh,
                    onGoToTab: _go,
                  ),
                  DiningScreen(result: _dining),
                  EventsScreen(result: _events),
                  CampusScreen(api: widget.api, areas: _areas),
                ],
              ),
            ),
            AppTabBar(tabs: _tabs, index: _index, onSelect: _go),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const List<LogicalKeyboardKey> _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

class _Masthead extends StatelessWidget {
  const _Masthead({required this.scheme});

  final SchemeController scheme;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final state = scheme.state;

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 12),
      child: Row(
        children: [
          Text(
            AppConfig.appName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 30),
          ),
          const Spacer(),
          // The palette escape hatch. An unusual wallpaper can produce an
          // unreadable scheme, so pinning the known-good seed is always one
          // tap away rather than requiring a rebuild.
          Tooltip(
            message: state.isDynamic
                ? 'Theme source: wallpaper\n${state.detail ?? ''}\nTap to use the built-in palette'
                : 'Theme source: built-in palette\n${state.detail ?? ''}\nTap to follow the wallpaper',
            child: InkWell(
              onTap: () => scheme.setForceSeed(!scheme.forcedToSeed),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  state.isDynamic
                      ? Icons.palette_rounded
                      : Icons.lock_outline_rounded,
                  size: 24,
                  color: state.isDynamic
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
