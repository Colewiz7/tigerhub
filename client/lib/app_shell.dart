/// App shell: the tab bar plus the four areas behind it.
///
/// Tabs are per area, and the home tab keeps the reorderable card grid. The
/// "+N more" footers navigate here, which is what makes them real rather than
/// decorative.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import 'data/shuttles.dart';
import 'home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/setup/setup_flow.dart';
import 'screens/setup/setup_kit.dart' show setupRoute;
import 'services/dashboard.dart';
import 'widgets/whats_new_sheet.dart';
import 'models/api_models.dart';
import 'screens/campus_screen.dart';
import 'screens/dining_screen.dart';
import 'screens/events_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/cache.dart';
import 'services/frame_monitor.dart';
import 'services/setup_draft.dart' show hasExistingData;
import 'services/subscriptions.dart';
import 'services/preferences.dart';
import 'services/api.dart';
import 'widgets/app_icon.dart';
import 'widgets/large_title.dart';
import 'theme/dynamic_theme.dart';
import 'theme/tokens.dart';
import 'widgets/tab_bar.dart';

const List<TabSpec> _tabs = [
  TabSpec(icon: AppIconKind.todayTab, selectedIcon: AppIconKind.todayTabSelected, label: 'Today'),
  TabSpec(icon: AppIconKind.diningTab, selectedIcon: AppIconKind.dining, label: 'Dining'),
  TabSpec(icon: AppIconKind.eventsTab, selectedIcon: AppIconKind.eventsTabSelected, label: 'Events'),
  TabSpec(icon: AppIconKind.mapTab, selectedIcon: AppIconKind.mapTabSelected, label: 'Map'),
  TabSpec(icon: AppIconKind.campusTab, selectedIcon: AppIconKind.campusTabSelected, label: 'Campus'),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.scheme,
    this.minimizeTabBarOnScroll = AppTabBar.minimizeOnScroll,
  });

  final ApiClient api;
  final SchemeController scheme;
  final bool minimizeTabBarOnScroll;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _showSettings = false;
  bool _barMinimized = false;
  // the glass bar scrolls lists in here
  final _content = GlobalKey();

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
    unawaited(ShuttleSchedule.load());
    _refresh();
    _ticker = Timer.periodic(_tick, (_) => _refresh());
    WidgetsBinding.instance.addObserver(this);
  }

  /// A phone suspends the app and its timers with it, so the ticker above does
  /// not run in a pocket. Coming back asks once immediately, through the same
  /// path as a tick, so every source's cadence still decides what is scraped.
  /// Without it, reopening after lunch shows lunch's occupancy.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _subscriptions.dispose();
    Preferences.instance.removeListener(_onPreferences);
    super.dispose();
  }

  // someone who already has settings gets the sheet, not the full flow
  bool? _existing;
  bool _detecting = false;

  void _onPreferences() {
    final prefs = Preferences.instance;
    if (prefs.loaded && !prefs.setupSeen && _existing == null && !_detecting) {
      _detecting = true;
      hasExistingData().then((found) {
        if (!mounted) return;
        setState(() => _existing = found);
        if (found) WidgetsBinding.instance.addPostFrameCallback((_) => _offerWhatsNew());
      });
    }
    if (mounted) setState(() {});
  }

  bool _offered = false;

  /// Once, for someone with settings from before setup existed. Either button
  /// counts as an answer, and so does closing the sheet.
  Future<void> _offerWhatsNew() async {
    if (!mounted || _offered || Preferences.instance.setupSeen) return;
    _offered = true;
    final result = await showWhatsNewSheet(context);
    // a dismissal is not an answer, so it asks again next launch
    if (result == WhatsNewResult.dismissed) return;
    await Preferences.instance.markSetupSeen();
    if (result == WhatsNewResult.personalize && mounted) await _openPersonalize();
  }

  /// Setup again, from what is stored, ending in Save or Cancel.
  Future<void> _openPersonalize() async {
    final dashboard = await DashboardStore.load();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    void close() => navigator.pop();
    await navigator.push(
      setupRoute<void>(
        context,
        (_) => SetupFlow(
          rerun: true,
          scheme: widget.scheme,
          areas: _areas.value?.data ?? const [],
          dining: _dining.value?.data ?? const [],
          events: _events.value?.data ?? const [],
          dashboard: dashboard,
          onDone: close,
          onCancel: close,
        ),
      ),
    );
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

  void _go(int index) {
    if (index != _index) FrameMonitor.instance.tabSwitched(index);
    setState(() => _index = index);
  }

  /// Marks scrolls for the frame stats. Never handles the notification.
  bool _onScroll(ScrollNotification n) {
    if (widget.minimizeTabBarOnScroll && n is UserScrollNotification && n.metrics.axis == Axis.vertical) {
      // reverse is the finger pushing content up
      final minimized = switch (n.direction) {
        ScrollDirection.reverse => true,
        ScrollDirection.forward => false,
        ScrollDirection.idle => _barMinimized,
      };
      if (minimized != _barMinimized) setState(() => _barMinimized = minimized);
    }
    return FrameMonitor.instance.onScroll(n, _index);
  }

  /// First run only, and only once the areas are in hand.
  ///
  /// It is never shown before the data arrives, because a setup screen with no
  /// choices on it is worse than a moment's wait, and the areas come from
  /// bundled config so that wait is not a network round trip.
  bool get _needsSetup =>
      Preferences.instance.loaded &&
      !Preferences.instance.setupSeen &&
      _existing == false &&
      (_areas.value?.data.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const tabs = _tabs;

    if (_needsSetup) {
      return SetupFlow(
        scheme: widget.scheme,
        areas: _areas.value!.data,
        dining: _dining.value?.data ?? const [],
        events: _events.value?.data ?? const [],
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
    // read above the Scaffold, which zeroes it for the body
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
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
            for (var i = 0; i < tabs.length && i < _digits.length; i++)
              SingleActivator(_digits[i]): () => _go(i),
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
            // the bar handles the bottom safe area itself
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // today heads itself, map stays full height, and the tab bar
                  // already names dining and events
                  if (_showSettings)
                    _SettingsHeader(
                      onClose: () => setState(() => _showSettings = false),
                    )
                  else if (_index == 1 || _index == 2)
                    SpokenTitle(tabs[_index].label)
                  else if (_index != 0 && _index != 3)
                    LargeTitle(tabs[_index].label),
                  Expanded(
                    // content runs to the screen bottom, under the bar
                    child: Builder(
                      builder: (context) => Stack(
                        children: [
                          Positioned.fill(
                            child: TabBarInset(
                              key: _content,
                              bottom: keyboardUp ? 0 : AppTabBar.overlap(context) + AppTabBar.contentGap,
                              child: _showSettings
                                  ? SettingsScreen(
                                      scheme: widget.scheme,
                                      events: _events,
                                      onPersonalize: _openPersonalize,
                                    )
                                  : NotificationListener<ScrollNotification>(
                                      onNotification: _onScroll,
                                      child: _TabStack(
                                        index: _index,
                                        children: [
                                          HomeScreen(
                                            api: widget.api,
                                            dining: _dining,
                                            events: _events,
                                            chefs: _chefs,
                                            areas: _areas,
                                            onRefresh: _refreshFromUser,
                                            onGoToTab: _go,
                                            onOpenSettings: () => setState(() => _showSettings = true),
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
                            ),
                          ),
                          // the bar never rides on top of the keyboard
                          if (!keyboardUp)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: AppTabBar(
                                tabs: tabs,
                                index: _index,
                                active: !_showSettings,
                                minimized: _barMinimized,
                                content: _content,
                                onSelect: (i) {
                                  if (_showSettings) {
                                    setState(() => _showSettings = false);
                                  }
                                  _go(i);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
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

/// Every tab stays mounted; only the current one is painted, hit-tested,
/// focusable or ticking. Switching is instant.
class _TabStack extends StatefulWidget {
  const _TabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack> {
  late final List<FocusScopeNode> _scopes = [
    for (final _ in widget.children) FocusScopeNode(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusActive());
  }

  @override
  void didUpdateWidget(_TabStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusActive());
    }
  }

  @override
  void dispose() {
    for (final scope in _scopes) {
      scope.dispose();
    }
    super.dispose();
  }

  /// A hidden tab cannot take its autofocus, so the active one asks for it
  /// when it appears. A screen with no autofocus node focuses its own scope,
  /// which keeps Tab traversal and the shell's key bindings working. Never a
  /// text field, so no keyboard opens, and never while focus is already in
  /// the tab.
  void _focusActive() {
    if (!mounted) return;
    final scope = _scopes[widget.index];
    if (scope.hasFocus) return;
    for (final node in scope.descendants) {
      final context = node.context;
      final focus = context?.widget;
      final text = context?.findAncestorWidgetOfExactType<EditableText>() != null;
      if (focus is Focus && focus.autofocus && !text && node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
    // requestFocus would walk back into a remembered search field
    scope.requestScopeFocus();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.index;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != active,
            child: ExcludeFocus(
              excluding: i != active,
              child: ExcludeSemantics(
                excluding: i != active,
                child: TickerMode(
                  enabled: i == active,
                  child: FocusScope(
                    node: _scopes[i],
                    child: widget.children[i],
                  ),
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
  LogicalKeyboardKey.digit5,
];

/// Settings is a screen of its own: a large title and Close.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(child: LargeTitle('Settings')),
      Padding(
        padding: EdgeInsets.only(top: 4, right: Insets.phone(context) ? 6 : 16),
        child: HeaderIconButton(
          icon: AppIconKind.close,
          tooltip: 'Close settings',
          onTap: onClose,
        ),
      ),
    ],
  );
}
