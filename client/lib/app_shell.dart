/// App shell: the tab bar plus the four areas behind it.
///
/// Tabs are per area, and the home tab keeps the reorderable card grid. The
/// "+N more" footers navigate here, which is what makes them real rather than
/// decorative.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'screens/setup_screen.dart';
import 'models/api_models.dart';
import 'screens/campus_screen.dart';
import 'screens/dining_screen.dart';
import 'screens/events_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/cache.dart';
import 'services/preferences.dart';
import 'services/api.dart';
import 'widgets/wordmark.dart';
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
  bool _showSettings = false;
  bool _animateTabChange = true;

  // Mirrored here so Settings and the Today grid stay in step.
  List<String> _cards = const ['dining', 'events', 'chefs', 'housing'];
  List<String> _hiddenCards = const [];

  Result<Collection<DiningLocation>> _dining = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<CampusEvent>> _events = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<MenuItem>> _chefs = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<HousingArea>> _areas = const Result(
    value: null,
    state: DataState.priming,
  );

  Timer? _ticker;

  /// How often to ask for a refresh while the window is open.
  ///
  /// Deliberately shorter than any source's cadence. Asking is nearly free:
  /// `LocalBackend` serves the read from memory and only actually scrapes a
  /// source whose snapshot has aged past its own interval, so this ticks at two
  /// minutes and occupancy still refreshes every five while events still
  /// refresh every three hours.
  ///
  /// Without it, an app left open all day shows the data it had at launch.
  /// Live occupancy in particular is not live if nothing asks again.
  static const Duration _tick = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    // Listened to, not just loaded: `loaded` and `setupSeen` both decide
    // whether the setup screen shows, and both flip asynchronously.
    Preferences.instance.addListener(_onPreferences);
    Preferences.instance.load();
    // Housekeeping, not on the critical path: nothing waits on it and a
    // failure is swallowed.
    unawaited(ResponseCache.instance.prune());
    _restoreCards();
    _refresh();
    _ticker = Timer.periodic(_tick, (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    Preferences.instance.removeListener(_onPreferences);
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreCards() async {
    final cache = ResponseCache.instance;
    final order = await cache.readOrder('cards');
    final hidden = await cache.readOrder('cards_hidden');
    if (!mounted) return;
    setState(() {
      if (order.isNotEmpty) _cards = order;
      _hiddenCards = hidden;
    });
  }

  Future<void> _setCards(List<String> order, List<String> hidden) async {
    setState(() {
      _cards = order;
      _hiddenCards = hidden;
    });
    await ResponseCache.instance.writeOrder('cards', order);
    await ResponseCache.instance.writeOrder('cards_hidden', hidden);
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

  void _go(int index, {bool animate = true}) => setState(() {
    _animateTabChange = animate;
    _index = index;
  });

  /// First run only, and only once the areas are in hand.
  ///
  /// It is never shown before the data arrives, because a setup screen with no
  /// choices on it is worse than a moment's wait, and the areas come from
  /// bundled config so that wait is not a network round trip.
  bool get _needsSetup =>
      Preferences.instance.loaded &&
      !Preferences.instance.setupSeen &&
      (_areas.value?.data.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_needsSetup) {
      return SetupScreen(
        areas: _areas.value!.data,
        onDone: () => setState(() {}),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      // Digit keys jump between tabs. Standard on a desktop app, and it also
      // makes the UI drivable for screenshots.
      body: CallbackShortcuts(
        bindings: {
          for (var i = 0; i < _tabs.length; i++)
            SingleActivator(_digits[i]): () => _go(i, animate: false),
          // Conventional settings shortcut.
          const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
              setState(() => _showSettings = !_showSettings),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              setState(() => _showSettings = false),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Column(
              children: [
                _Masthead(
                  scheme: widget.scheme,
                  settingsOpen: _showSettings,
                  onSettings: () =>
                      setState(() => _showSettings = !_showSettings),
                ),
                Expanded(
                  child: _showSettings
                      ? SettingsScreen(
                          scheme: widget.scheme,
                          events: _events,
                          cards: _cards,
                          hiddenCards: _hiddenCards,
                          onCardsChanged: _setCards,
                        )
                      : _TabStack(
                          index: _index,
                          animate: _animateTabChange,
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
                            DiningScreen(result: _dining, api: widget.api),
                            EventsScreen(result: _events),
                            CampusScreen(
                              api: widget.api,
                              areas: _areas,
                              events: _events,
                            ),
                          ],
                        ),
                ),
                AppTabBar(
                  tabs: _tabs,
                  index: _showSettings ? -1 : _index,
                  onSelect: (i) {
                    if (_showSettings) {
                      setState(() => _showSettings = false);
                    }
                    _go(i);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabStack extends StatelessWidget {
  const _TabStack({
    required this.index,
    required this.animate,
    required this.children,
  });

  final int index;
  final bool animate;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final duration = reduceMotion || !animate
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var childIndex = 0; childIndex < children.length; childIndex++)
          IgnorePointer(
            ignoring: childIndex != index,
            child: ExcludeSemantics(
              excluding: childIndex != index,
              child: TickerMode(
                enabled: childIndex == index,
                child: AnimatedOpacity(
                  opacity: childIndex == index ? 1 : 0,
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: children[childIndex],
                ),
              ),
            ),
          ),
      ],
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
  const _Masthead({
    required this.scheme,
    required this.settingsOpen,
    required this.onSettings,
  });

  final SchemeController scheme;
  final bool settingsOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final state = scheme.state;

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 12),
      child: Row(
        children: [
          Image.asset(
            'assets/images/tigerhub-mascot.png',
            height: 44,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 8),
          const Wordmark(),
          const Spacer(),
          Tooltip(
            message: settingsOpen ? 'Close settings' : 'Settings',
            child: InkWell(
              onTap: onSettings,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  settingsOpen ? Icons.close_rounded : Icons.settings_rounded,
                  size: 24,
                  color: settingsOpen
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
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
