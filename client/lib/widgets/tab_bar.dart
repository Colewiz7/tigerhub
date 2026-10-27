/// The tab bar.
///
/// iOS gets a floating glass capsule with a sliding selection pill. Android
/// and Linux keep a Material NavigationBar. Content scrolls under both, and
/// [TabBarInset] tells each scrollable how far to pad its end.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../motion/gesture.dart';
import '../motion/reduce_motion.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

class TabSpec {
  const TabSpec({required this.icon, required this.selectedIcon, required this.label});

  final AppIconKind icon;
  final AppIconKind selectedIcon;
  final String label;
}

/// Space the floating bar takes from the bottom of the content area.
/// Zero outside the shell, or while the bar is hidden.
class TabBarInset extends InheritedWidget {
  const TabBarInset({super.key, required this.bottom, required super.child});

  final double bottom;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabBarInset>()?.bottom ?? 0;

  // the bar's inset replaces the list's own end padding
  static EdgeInsets pad(BuildContext context, EdgeInsets base) {
    final bottom = of(context);
    return bottom == 0 ? base : base.copyWith(bottom: bottom);
  }

  @override
  bool updateShouldNotify(TabBarInset old) => old.bottom != bottom;
}

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelect,
    this.active = true,
    this.minimized = false,
  });

  final List<TabSpec> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// False while a screen outside the tabs (Settings) covers them.
  final bool active;

  /// iOS only: icons alone in a shorter capsule.
  final bool minimized;

  static const double capsuleHeight = 60;
  static const double minimizedHeight = 48;
  static const double sideInset = 16;
  static const double materialHeight = 80;

  /// Gap between the bar and the last row a list can scroll to.
  static const double contentGap = 8;

  /// Off until a device test says otherwise. Build with
  /// --dart-define=MINIMIZE_TAB_BAR=true to try it.
  static const bool minimizeOnScroll = bool.fromEnvironment('MINIMIZE_TAB_BAR');

  static bool glass(BuildContext context) => Theme.of(context).platform == TargetPlatform.iOS;

  // above the home indicator, or a side inset off the edge without one
  static double capsuleBottom(BuildContext context) => math.max(MediaQuery.paddingOf(context).bottom, sideInset);

  /// Height from the bottom of the screen to the top of the bar.
  static double overlap(BuildContext context) =>
      glass(context) ? capsuleHeight + capsuleBottom(context) : materialHeight + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    if (glass(context)) {
      return _GlassTabBar(tabs: tabs, index: index, onSelect: onSelect, active: active, minimized: minimized);
    }
    return NavigationBar(
      height: materialHeight,
      selectedIndex: index,
      onDestinationSelected: onSelect,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      // no selection shown while settings covers the tabs
      indicatorColor: active ? null : Colors.transparent,
      destinations: [
        for (final tab in tabs)
          NavigationDestination(
            icon: Icon(tab.icon.of(context)),
            selectedIcon: Icon((active ? tab.selectedIcon : tab.icon).of(context)),
            label: tab.label,
          ),
      ],
    );
  }
}

class _GlassTabBar extends StatefulWidget {
  const _GlassTabBar({
    required this.tabs,
    required this.index,
    required this.onSelect,
    required this.active,
    required this.minimized,
  });

  final List<TabSpec> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final bool active;
  final bool minimized;

  @override
  State<_GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<_GlassTabBar> with SingleTickerProviderStateMixin {
  static const double _pad = 4;

  // pill position in tabs, fractional mid slide or mid scrub
  late final AnimationController _pill = AnimationController.unbounded(vsync: this, value: widget.index.toDouble());

  bool _scrubbing = false;
  int _lastTab = 0;
  double _downX = 0;
  double _downPill = 0;
  double _finger = 0;
  _Chase? _chase;
  double _carry = 0;
  // taps settle outside layout
  double _laidOutItemWidth = 0;
  final _tracker = ReleaseTracker();
  double _upTime = 0;
  late int _target;

  @override
  void initState() {
    super.initState();
    _target = widget.index;
  }

  @override
  void didUpdateWidget(_GlassTabBar old) {
    super.didUpdateWidget(old);
    // release already picked the tab
    if (old.index != widget.index && !_scrubbing && widget.index != _target) _settle(widget.index);
  }

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  void _settle(int tab, [double? velocity]) {
    _target = tab;
    final itemWidth = _laidOutItemWidth;
    if (reduceMotion(context) || itemWidth == 0) {
      _pill.value = tab.toDouble();
      return;
    }
    final px = settle(_pill.value * itemWidth, tab * itemWidth, velocity ?? _pill.velocity * itemWidth, const Duration(milliseconds: 180));
    // the spring stops within tolerance, land exactly
    _pill.animateWith(_InTabs(px, itemWidth)).then((_) => _pill.value = tab.toDouble());
  }

  double _itemWidth(double width) => (width - _pad * 2) / widget.tabs.length;

  void _startScrub(double x) {
    _carry = _pill.velocity;
    _pill.stop();
    _downX = x;
    _downPill = _pill.value;
    _finger = _pill.value;
    setState(() {
      _scrubbing = true;
      _lastTab = _pill.value.round();
    });
  }

  // 1:1 with the finger since touch down
  void _scrubTo(double x, double width) {
    final itemWidth = _itemWidth(width);
    final px = _downPill * itemWidth + x - _downX;
    final end = (widget.tabs.length - 1) * itemWidth;
    _finger = (px < 0 ? rubberband(px, width) : (px > end ? end + rubberband(px - end, width) : px)) / itemWidth;
    final chase = _chase;
    if (reduceMotion(context)) {
      _pill.value = _finger;
    } else if (chase != null && _pill.isAnimating) {
      chase.retarget(_finger, (_pill.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6);
    } else {
      // at rest on the finger, start a fresh chase
      final fresh = _Chase(_pill.value, _carry, itemWidth)..retarget(_finger, 0);
      _chase = fresh;
      _carry = 0;
      _pill.animateWith(fresh).then((_) => _pill.value = fresh.target);
    }
    final tab = _finger.round().clamp(0, widget.tabs.length - 1);
    for (var i = 0; i < (tab - _lastTab).abs(); i++) {
      HapticFeedback.selectionClick();
    }
    if (tab != _lastTab) setState(() => _lastTab = tab);
  }

  double _ms(Duration time) => time.inMicroseconds / 1000;

  void _endScrub(double itemWidth, double velocity) {
    if (!_scrubbing) return;
    final tab = (_finger + project(velocity, 0.99) / itemWidth).round().clamp(0, widget.tabs.length - 1);
    setState(() => _scrubbing = false);
    if (tab != widget.index) HapticFeedback.lightImpact();
    _settle(tab, velocity);
    if (tab != widget.index || !widget.active) widget.onSelect(tab);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = widget.minimized ? AppTabBar.minimizedHeight : AppTabBar.capsuleHeight;
    final radius = BorderRadius.circular(height / 2);
    final count = widget.tabs.length;
    final highlighted = _scrubbing ? _lastTab : (widget.active ? widget.index : -1);

    return Padding(
      padding: EdgeInsets.fromLTRB(AppTabBar.sideInset, 0, AppTabBar.sideInset, AppTabBar.capsuleBottom(context)),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final itemWidth = _laidOutItemWidth = _itemWidth(width);
            final bar = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final tab = ((d.localPosition.dx - _pad) / itemWidth).floor().clamp(0, count - 1);
                widget.onSelect(tab);
              },
              // slop lands in first update
              dragStartBehavior: DragStartBehavior.down,
              // horizontal only, so a vertical swipe never starts a scrub
              onHorizontalDragStart: (d) => _startScrub(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx, width),
              // flutter zeroes short flicks
              onHorizontalDragEnd: (_) => _endScrub(itemWidth, _tracker.velocity(_upTime)),
              onHorizontalDragCancel: () => _endScrub(itemWidth, 0),
              // claims vertical moves, or horizontal wins them by default
              onVerticalDragStart: (_) {},
              child: Semantics(
                role: ui.SemanticsRole.tabBar,
                container: true,
                explicitChildNodes: true,
                child: ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer.withValues(alpha: 0.7),
                        borderRadius: radius,
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: Stack(
                        children: [
                          if (widget.active || _scrubbing)
                            AnimatedBuilder(
                              animation: _pill,
                              builder: (context, child) => Positioned(
                                key: const ValueKey('tab-pill'),
                                left: _pad + _pill.value * itemWidth,
                                top: _pad,
                                bottom: _pad,
                                width: itemWidth,
                                child: child!,
                              ),
                              child: DecoratedBox(
                                decoration: ShapeDecoration(color: scheme.secondaryContainer, shape: Shapes.pill),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(_pad),
                            child: Row(
                              children: [
                                for (var i = 0; i < count; i++)
                                  Expanded(
                                    child: _GlassItem(
                                      spec: widget.tabs[i],
                                      position: i,
                                      count: count,
                                      selected: i == highlighted,
                                      minimized: widget.minimized,
                                      onTap: () => widget.onSelect(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            return Listener(
              onPointerDown: (e) {
                _tracker.clear();
                _tracker.add(e.localPosition.dx, _ms(e.timeStamp));
              },
              onPointerMove: (e) => _tracker.add(e.localPosition.dx, _ms(e.timeStamp)),
              onPointerUp: (e) => _upTime = _ms(e.timeStamp),
              child: bar,
            );
          },
        ),
      ),
    );
  }
}

// chases the finger until release
class _Chase extends Simulation {
  _Chase(double from, double velocity, this.itemWidth) : target = from, _sim = SpringSimulation(_spring, from, from, velocity);

  static final _spring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 150));

  final double itemWidth;
  double target;
  SpringSimulation _sim;
  double _t0 = 0;

  // retargets keep the pill's velocity
  void retarget(double target, double now) {
    _sim = SpringSimulation(_spring, x(now), target, dx(now));
    this.target = target;
    _t0 = now;
  }

  @override
  double x(double time) => _sim.x(time - _t0);

  @override
  double dx(double time) => _sim.dx(time - _t0);

  // settle tolerance is pixels
  @override
  bool isDone(double time) => ((x(time) - target) * itemWidth).abs() < settleTolerance.distance && (dx(time) * itemWidth).abs() < settleTolerance.velocity;
}

// settle is pixels, pill is tabs
class _InTabs extends Simulation {
  _InTabs(this.px, this.itemWidth);

  final Simulation px;
  final double itemWidth;

  @override
  double x(double time) => px.x(time) / itemWidth;

  @override
  double dx(double time) => px.dx(time) / itemWidth;

  @override
  bool isDone(double time) => px.isDone(time);
}

class _GlassItem extends StatelessWidget {
  const _GlassItem({
    required this.spec,
    required this.position,
    required this.count,
    required this.selected,
    required this.minimized,
    required this.onTap,
  });

  final TabSpec spec;
  final int position;
  final int count;
  final bool selected;
  final bool minimized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 11,
      height: 1.2,
      letterSpacing: 0,
      fontWeight: AppTheme.weight(Weights.medium),
      fontVariations: Weights.medium,
      color: color,
    );

    return Semantics(
      container: true,
      role: ui.SemanticsRole.tab,
      selected: selected,
      label: '${spec.label}, tab ${position + 1} of $count',
      onTap: onTap,
      excludeSemantics: true,
      // a fixed 60pt capsule, so labels stop growing at 1.3x
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon((selected ? spec.selectedIcon : spec.icon).of(context), size: 24, color: color),
            if (!minimized) ...[
              const SizedBox(height: 2),
              Text(spec.label, style: label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
            ],
          ],
        ),
      ),
    );
  }
}
