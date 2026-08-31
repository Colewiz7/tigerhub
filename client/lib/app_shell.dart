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
import 'screens/map_screen.dart';
import 'screens/setup_screen.dart';
import 'models/api_models.dart';
import 'screens/campus_screen.dart';
import 'screens/dining_screen.dart';
import 'screens/events_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/cache.dart';
import 'services/dashboard.dart';
import 'services/subscriptions.dart';
import 'services/preferences.dart';
import 'services/api.dart';
import 'widgets/wordmark.dart';
import 'theme/dynamic_theme.dart';
import 'widgets/page_veil.dart';
import 'widgets/tab_bar.dart';

const List<TabSpec> _tabs = [
  TabSpec(icon: Icons.grid_view_rounded, label: 'TODAY'),
  TabSpec(icon: Icons.restaurant_rounded, label: 'DINING'),
  TabSpec(icon: Icons.event_note_rounded, label: 'EVENTS'),
  TabSpec(icon: Icons.map_rounded, label: 'MAP'),
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
  // Instance ids, not the old string ids, and derived from one place so this
  // cannot drift from what the store hands back.
  List<String> _cards = [for (final c in defaultDashboard) c.id];
  List<String> _hiddenCards = const [];
  List<CardInstance> _dashboard = defaultDashboard;

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
    _subscriptions.dispose();
    Preferences.instance.removeListener(_onPreferences);
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  /// Reads through the same store the Today grid writes.
  ///
  /// These used to be two independent readers and writers of the same two
  /// preference keys, which is how the shell and the grid could disagree about
  /// what was hidden.
  Future<void> _restoreCards() async {
    final loaded = await DashboardStore.load();
    if (!mounted) return;
    setState(() {
      _cards = [
        for (final c in loaded)
          if (!c.hidden) c.id,
      ];
      _hiddenCards = [
        for (final c in loaded)
          if (c.hidden) c.id,
      ];
      _dashboard = loaded;
    });
  }

  Future<void> _setCards(List<String> order, List<String> hidden) async {
    final byId = {for (final card in _dashboard) card.id: card};
    final rebuilt = <CardInstance>[
      for (final id in order)
        if (byId[id] != null) byId[id]!.copyWith(hidden: false),
      for (final card in _dashboard)
        if (!order.contains(card.id)) card.copyWith(hidden: true),
    ];

    setState(() {
      _cards = order;
      _hiddenCards = hidden;
      _dashboard = rebuilt;
    });
    await DashboardStore.save(rebuilt);
  }

  final _subscriptions = Subscriptions();

  /// The pull-to-refresh on the home screen.
  ///
  /// It used to call [_refresh], which is the same path the two minute ticker
  /// takes and therefore respects every source's cadence. Dining is hourly and
  /// campus places are twice a day, so pulling almost always fetched nothing
  /// while showing a spinner that implied otherwise.
  Future<void> _refreshFromUser() async {
    await widget.api.refreshNow();
    await _refresh();
  }

  Future<void> _refresh() async {
    // Replace the previous tick's subscriptions rather than stacking on them.
    // Without this the ticker added four every two minutes, and stale ones
    // kept delivering, so an older result could land after a newer one and
    // overwrite it.
    _subscriptions.cancelAll();

    _subscriptions
      ..add(
        widget.api.dining().listen((r) {
          if (mounted) setState(() => _dining = r);
        }),
      )
      ..add(
        widget.api.events().listen((r) {
          if (mounted) setState(() => _events = r);
        }),
      )
      ..add(
        widget.api.visitingChefs().listen((r) {
          if (mounted) setState(() => _chefs = r);
        }),
      )
      ..add(
        widget.api.housingAreas().listen((r) {
          if (mounted) setState(() => _areas = r);
        }),
      );
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

    // Android's back button.
    //
    // Without this, back exits the app from wherever you happen to be. Every
    // real Android app walks back to its home tab first, and leaving Settings
    // or the Campus tab by closing the whole app is a jarring way to lose your
    // place. Desktop is unaffected: there is no system back gesture there, and
    // the tab digits and the tab strip are untouched.
    final atHome = !_showSettings && _index == 0;
    return PopScope(
      canPop: atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showSettings) {
          setState(() => _showSettings = false);
        } else {
          _go(0);
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        // Digit keys jump between tabs. Standard on a desktop app, and it also
        // makes the UI drivable for screenshots.
        body: CallbackShortcuts(
          bindings: {
            for (var i = 0; i < _tabs.length && i < _digits.length; i++)
              SingleActivator(_digits[i]): () => _go(i, animate: false),
            // Conventional settings shortcut.
            const SingleActivator(
              LogicalKeyboardKey.comma,
              control: true,
            ): () =>
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
                                onRefresh: _refreshFromUser,
                                onGoToTab: _go,
                              ),
                              DiningScreen(result: _dining, api: widget.api),
                              EventsScreen(result: _events),
                              MapScreen(api: widget.api, events: _events),
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
      ),
    );
  }
}

/// The four tabs, keeping every screen's state while only paying for the ones
/// on screen.
///
/// A plain Stack of all four laid out and composited every screen at once,
/// which got noticeably worse when the campus map arrived: a map canvas was
/// being laid out continuously while nobody was looking at it.
///
/// So everything except the tab being shown, and the one being faded out, is
/// Offstage. Offstage keeps the State alive, and therefore scroll positions,
/// subscriptions and any in progress edit, while skipping layout and paint
/// entirely. The crossfade the motion spec asks for still happens, because the
/// outgoing tab stays on stage until it finishes.
class _TabStack extends StatefulWidget {
  const _TabStack({
    required this.index,
    required this.animate,
    required this.children,
  });

  final int index;
  final bool animate;
  final List<Widget> children;

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack> {
  /// The tab fading out, kept on stage until the fade ends.
  int? _outgoing;
  Timer? _settle;

  /// Covers the content while the incoming tab comes up. Without it you watch
  /// a tab assemble, which looks broken. The Map tab is the
  /// honest case: it lays out a canvas and builds its geometry from cold.
  bool _veiled = false;
  Timer? _unveil;

  @override
  void didUpdateWidget(_TabStack old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;

    _settle?.cancel();
    setState(() => _outgoing = old.index);

    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);

    if (reduceMotion || !widget.animate) {
      _outgoing = null;
      return;
    }

    _veiled = true;
    _unveil?.cancel();
    _unveil = Timer(PageVeil.hold, () {
      if (mounted) setState(() => _veiled = false);
    });

    _settle = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _outgoing = null);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _unveil?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final duration = reduceMotion || !widget.animate
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (
          var childIndex = 0;
          childIndex < widget.children.length;
          childIndex++
        )
          Offstage(
            offstage: childIndex != widget.index && childIndex != _outgoing,
            child: IgnorePointer(
              ignoring: childIndex != widget.index,
              child: ExcludeSemantics(
                excluding: childIndex != widget.index,
                child: TickerMode(
                  enabled: childIndex == widget.index,
                  child: AnimatedOpacity(
                    opacity: childIndex == widget.index ? 1 : 0,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: widget.children[childIndex],
                  ),
                ),
              ),
            ),
          ),
        // Over everything, so the incoming tab assembles out of sight.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _veiled ? 1 : 0,
              duration: PageVeil.fade,
              curve: Curves.easeOutCubic,
              child: _veiled
                  ? PageVeil(label: _tabs[widget.index].label)
                  : const SizedBox.shrink(),
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
  LogicalKeyboardKey.digit5,
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
            child: Semantics(
              button: true,
              toggled: settingsOpen,
              label: settingsOpen ? 'Close settings' : 'Open settings',
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
          ),
          const SizedBox(width: 4),
          // The palette escape hatch. An unusual wallpaper can produce an
          // unreadable scheme, so pinning the known-good seed is always one
          // tap away rather than requiring a rebuild.
          Tooltip(
            message: state.isDynamic
                ? 'Theme source: wallpaper\n${state.detail ?? ''}\nTap to use the built-in palette'
                : 'Theme source: built-in palette\n${state.detail ?? ''}\nTap to follow the wallpaper',
            child: Semantics(
              button: true,
              toggled: !state.isDynamic,
              label: state.isDynamic
                  ? 'Use built-in color palette'
                  : 'Follow wallpaper colors',
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
          ),
        ],
      ),
    );
  }
}
