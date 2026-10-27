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
    this.content,
  });

  final List<TabSpec> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// False while a screen outside the tabs (Settings) covers them.
  final bool active;

  /// iOS only: icons alone in a shorter capsule.
  final bool minimized;

  /// iOS only: what the capsule floats over. A vertical swipe on the capsule
  /// scrolls the list in it under the finger.
  final GlobalKey? content;

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
      return _GlassTabBar(tabs: tabs, index: index, onSelect: onSelect, active: active, minimized: minimized, content: content);
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
    required this.content,
  });

  final List<TabSpec> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final bool active;
  final bool minimized;
  final GlobalKey? content;

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
  // the first finger down owns the scrub
  int? _owner;
  double _ownerDownX = 0;
  double _ownerX = 0;
  Drag? _listDrag;
  VelocityTracker? _listVelocity;
  ScrollPhysics? _listPhysics;
  late int _target;

  @override
  void initState() {
    super.initState();
    _target = widget.index;
  }

  @override
  void didUpdateWidget(_GlassTabBar old) {
    super.didUpdateWidget(old);
    // the list being dragged is now hidden
    if (old.index != widget.index || old.active != widget.active) _listDrag?.cancel();
    // release already picked the tab
    if (old.index != widget.index && !_scrubbing && widget.index != _target) _settle(widget.index);
  }

  @override
  void dispose() {
    _listDrag?.cancel();
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
    if (!_scrubbing) return;
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

  // the bar takes the touch, so it scrolls the list under the finger itself
  void _listStart(List<PointerEvent> since) {
    final down = since.first;
    final last = since.last;
    final root = widget.content?.currentContext;
    final list = root == null ? null : _listAt(root, down.position);
    if (list == null) return;
    _listPhysics = list.position.physics;
    // velocity from touch down
    final tracker = ScrollConfiguration.of(list.context).velocityTrackerBuilder(list.context)(down);
    for (final event in since) {
      tracker.addPosition(event.timeStamp, event.position);
    }
    _listVelocity = tracker;
    _listDrag = list.position.drag(DragStartDetails(sourceTimeStamp: last.timeStamp, globalPosition: last.position, localPosition: last.localPosition, kind: down.kind), () => _listDrag = null);
  }

  void _listUpdate(PointerEvent event) {
    _listVelocity?.addPosition(event.timeStamp, event.position);
    _listDrag?.update(DragUpdateDetails(sourceTimeStamp: event.timeStamp, delta: Offset(0, event.delta.dy), primaryDelta: event.delta.dy, globalPosition: event.position, localPosition: event.localPosition));
  }

  // the same fling limits the list's own drag applies
  void _listEnd() {
    final drag = _listDrag;
    final physics = _listPhysics;
    if (drag == null || physics == null) return;
    final estimate = _listVelocity?.getVelocityEstimate();
    final v = estimate?.pixelsPerSecond.dy ?? 0;
    final flung = v.abs() > physics.minFlingVelocity && (estimate?.offset.dy.abs() ?? 0) > physics.minFlingDistance;
    final fling = flung ? v.clamp(-physics.maxFlingVelocity, physics.maxFlingVelocity) : 0.0;
    drag.end(DragEndDetails(velocity: Velocity(pixelsPerSecond: Offset(0, fling)), primaryVelocity: fling));
  }

  // the system took the touch, nothing was chosen
  void _cancelScrub() {
    if (!_scrubbing) return;
    setState(() => _scrubbing = false);
    _settle(widget.index);
  }

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
            final bar = RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _BarGestures: GestureRecognizerFactoryWithHandlers<_BarGestures>(_BarGestures.new, (bar) {
                  bar.onTap = (x) => widget.onSelect(((x - _pad) / itemWidth).floor().clamp(0, count - 1));
                  // starts from touch down, the slop lands in the first update
                  bar.onScrubStart = () => _startScrub(_ownerDownX);
                  bar.onScrubUpdate = () => _scrubTo(_ownerX, width);
                  // the owner lifting already ended it
                  bar.onScrubEnd = () => _endScrub(itemWidth, 0);
                  bar.onScrubCancel = _cancelScrub;
                  bar.onListStart = _listStart;
                  bar.onListUpdate = _listUpdate;
                  bar.onListEnd = _listEnd;
                  bar.onListCancel = () => _listDrag?.cancel();
                }),
              },
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
            final owned = Listener(
              onPointerDown: (e) {
                if (_owner != null) return;
                _owner = e.pointer;
                _ownerDownX = _ownerX = e.localPosition.dx;
                _tracker.clear();
                _tracker.add(_ownerX, _ms(e.timeStamp));
              },
              onPointerMove: (e) {
                if (e.pointer != _owner) return;
                _ownerX = e.localPosition.dx;
                _tracker.add(_ownerX, _ms(e.timeStamp));
              },
              // flutter zeroes short flicks
              onPointerUp: (e) {
                if (e.pointer != _owner) return;
                _owner = null;
                _endScrub(itemWidth, _tracker.velocity(_ms(e.timeStamp)));
              },
              onPointerCancel: (e) {
                if (e.pointer != _owner) return;
                _owner = null;
                _tracker.clear();
                _cancelScrub();
              },
              child: bar,
            );
            return owned;
          },
        ),
      ),
    );
  }
}

// tap, scrub and list drag in one, the bar owns every touch on it
class _BarGestures extends OneSequenceGestureRecognizer {
  ValueChanged<double>? onTap;
  VoidCallback? onScrubStart;
  VoidCallback? onScrubUpdate;
  VoidCallback? onScrubEnd;
  VoidCallback? onScrubCancel;
  ValueChanged<List<PointerEvent>>? onListStart;
  ValueChanged<PointerEvent>? onListUpdate;
  VoidCallback? onListEnd;
  VoidCallback? onListCancel;

  int? _primary;
  Offset _down = Offset.zero;
  bool _moved = false;
  bool _won = false;
  bool _scrubbing = false;
  bool _listing = false;
  // down and every move before the slop
  final _since = <PointerEvent>[];
  // a tap lifted before the arena chose
  int? _upPointer;
  double _upX = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    if (_primary != null) {
      // extra fingers are the bar's and do nothing
      resolvePointer(event.pointer, GestureDisposition.accepted);
      return;
    }
    _primary = event.pointer;
    _down = event.localPosition;
    _moved = false;
    _won = false;
    _scrubbing = false;
    _listing = false;
    _upPointer = null;
    _since
      ..clear()
      ..add(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _primary) {
      if (event is PointerUpEvent || event is PointerCancelEvent) stopTrackingPointer(event.pointer);
      return;
    }
    final d = event.localPosition - _down;
    final slop = computeHitSlop(event.kind, gestureSettings);
    if (event is PointerMoveEvent) {
      if (!_moved && d.distance > slop) {
        _moved = true;
        if (!_won) resolvePointer(event.pointer, GestureDisposition.accepted);
        // clear sideways intent scrubs, anything else drives the list
        if (d.dx.abs() > d.dy.abs() * 1.5) {
          _scrubbing = true;
          onScrubStart?.call();
        } else {
          _listing = true;
          onListStart?.call(List.of(_since));
        }
      }
      if (!_moved) _since.add(event);
      if (_scrubbing) onScrubUpdate?.call();
      if (_listing) onListUpdate?.call(event);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_scrubbing) {
        event is PointerCancelEvent ? onScrubCancel?.call() : onScrubEnd?.call();
      } else if (_listing) {
        event is PointerCancelEvent ? onListCancel?.call() : onListEnd?.call();
      } else if (event is PointerUpEvent && _won && !_moved) {
        onTap?.call(event.localPosition.dx);
      } else if (event is PointerUpEvent && !_moved) {
        _upPointer = event.pointer;
        _upX = event.localPosition.dx;
      }
      _primary = null;
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _primary) {
      _won = true;
    } else if (pointer == _upPointer) {
      _upPointer = null;
      onTap?.call(_upX);
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _upPointer) _upPointer = null;
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'tab bar';
}

// innermost vertical list under the point, hidden tabs skipped
ScrollableState? _listAt(BuildContext root, Offset point) {
  ScrollableState? found;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (element is StatefulElement && element.state is ScrollableState) {
      final list = element.state as ScrollableState;
      final box = element.findRenderObject();
      if (list.position.axis == Axis.vertical && box is RenderBox && box.hasSize && (box.localToGlobal(Offset.zero) & box.size).contains(point)) found = list;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return found;
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
