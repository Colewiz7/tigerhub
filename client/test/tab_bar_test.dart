/// The tab bar: a floating glass capsule on iOS, a Material NavigationBar
/// elsewhere, with content scrolling under both.
library;

import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

import 'support/tabs.dart';

class _Backend implements Backend {
  static String name(int id) => 'Place number $id';

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    final data = path == '/dining'
        ? [
            for (var i = 0; i < 20; i++)
              {'id': i, 'name': name(i), 'category': 'cat', 'category_name': 'Category', 'category_order': 0, 'is_open': true, 'today': <dynamic>[]},
          ]
        : <Map<String, dynamic>>[];
    return {'data': data, 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _material = TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux});
final _all = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.linux});

const _tabs = [
  TabSpec(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: 'Today'),
  TabSpec(icon: Icons.restaurant_outlined, selectedIcon: Icons.restaurant_rounded, label: 'Dining'),
  TabSpec(icon: Icons.event_note_outlined, selectedIcon: Icons.event_note_rounded, label: 'Events'),
  TabSpec(icon: Icons.map_outlined, selectedIcon: Icons.map_rounded, label: 'Map'),
  TabSpec(icon: Icons.location_city_outlined, selectedIcon: Icons.location_city_rounded, label: 'Campus'),
];

// an iphone with a home indicator, 34 at the bottom
void _phone(WidgetTester tester, Size size, {double top = 47}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(top: top, bottom: 34);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: 34);
  addTearDown(tester.view.reset);
}

Future<void> _pumpShell(WidgetTester tester, {bool minimize = false}) async {
  final scheme = SchemeController();
  await scheme.load();
  addTearDown(scheme.dispose);
  await tester.pumpWidget(MaterialApp(home: AppShell(api: ApiClient(backend: _Backend()), scheme: scheme, minimizeTabBarOnScroll: minimize)));
  await tester.pumpAndSettle();
}

ScrollableState _vertical(WidgetTester tester, Finder root) => tester
    .stateList<ScrollableState>(find.descendant(of: root, matching: find.byType(Scrollable)))
    .firstWhere((s) => s.position.axis == Axis.vertical);

// a bare bar that keeps its own selection, like the shell does
class _Host extends StatefulWidget {
  const _Host({this.selected});

  final List<int>? selected;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AppTabBar(
            tabs: _tabs,
            index: index,
            onSelect: (i) {
              widget.selected?.add(i);
              setState(() => index = i);
            },
          ),
        ),
      ],
    ),
  );
}

Future<void> _pumpBar(WidgetTester tester, {List<int>? selected, bool reduceMotion = false}) async {
  _phone(tester, const Size(390, 844));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
      home: _Host(selected: selected),
    ),
  );
  await tester.pumpAndSettle();
}

// 390 wide: a 358 capsule from x 16, 4 padding, five 70 wide items
const _itemWidth = 70.0;
double _tabCentre(int i) => 16 + 4 + _itemWidth * i + _itemWidth / 2;
double _pillLeft(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('tab-pill'))).left;
double _pillAt(double tabs) => 16 + 4 + _itemWidth * tabs;

List<String> _haptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  for (final (size, top) in const [(Size(390, 844), 47.0), (Size(440, 956), 62.0)]) {
    testWidgets('${size.width.toInt()}x${size.height.toInt()}: a 60pt glass capsule, 16 in, above the home indicator', (tester) async {
      _phone(tester, size, top: top);
      await _pumpShell(tester);

      expect(find.byType(BackdropFilter), findsOneWidget, reason: 'one blur for the whole bar');
      final capsule = tester.getRect(find.descendant(of: find.byType(AppTabBar), matching: find.byType(BackdropFilter)));
      expect(capsule.height, 60);
      expect(capsule.left, 16);
      expect(capsule.right, size.width - 16);
      expect(capsule.bottom, size.height - 34, reason: 'sits on the safe area, not in it');

      final clip = tester.widget<ClipRRect>(find.descendant(of: find.byType(AppTabBar), matching: find.byType(ClipRRect)));
      expect(clip.borderRadius, BorderRadius.circular(30), reason: 'full radius');

      final scheme = Theme.of(tester.element(find.byType(AppTabBar))).colorScheme;
      final glass = tester.widget<DecoratedBox>(find.descendant(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(glass.color, scheme.surfaceContainer.withValues(alpha: 0.7));
      expect(glass.border, Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3), width: 0.5));
      expect(glass.boxShadow, isNull);
      expect(find.byType(NavigationBar), findsNothing);
    }, variant: _ios);
  }

  testWidgets('content runs under the bar and the last row clears it', (tester) async {
    _phone(tester, const Size(390, 844));
    await _pumpShell(tester);
    await tester.tap(tabLabel('Dining'));
    await tester.pumpAndSettle();

    final dining = find.byType(DiningScreen);
    final list = _vertical(tester, dining);
    expect(tester.getRect(find.byWidget(list.widget)).bottom, 844, reason: 'the list stops at the bar, a flat clip line');

    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final barTop = tester.getRect(find.byType(AppTabBar)).top;
    final rows = find.descendant(of: dining, matching: find.textContaining('Place number'));
    final lastBottom = [for (final e in rows.evaluate()) tester.getRect(find.byWidget(e.widget)).bottom].reduce((a, b) => a > b ? a : b);
    expect(lastBottom, lessThanOrEqualTo(barTop - AppTabBar.contentGap), reason: 'the last row hides behind the bar');
  }, variant: _all);

  testWidgets('android and linux keep an 80dp edge to edge NavigationBar', (tester) async {
    _phone(tester, const Size(390, 844));
    await _pumpShell(tester);

    expect(find.byType(BackdropFilter), findsNothing);
    final bar = tester.getRect(find.byType(NavigationBar));
    expect(bar.height, 80 + 34);
    expect(bar.left, 0);
    expect(bar.right, 390);
    expect(bar.bottom, 844);
    for (final label in ['Today', 'Dining', 'Events', 'Map', 'Campus']) {
      expect(tabLabel(label), findsOneWidget, reason: 'sentence case $label');
    }
  }, variant: _material);

  testWidgets('the pill follows a scrub and clicks once per tab crossed', (tester) async {
    final haptics = _haptics(tester);
    final selected = <int>[];
    await _pumpBar(tester, selected: selected);
    final y = tester.getCenter(find.byType(BackdropFilter)).dy;

    var at = _tabCentre(0);
    final gesture = await tester.startGesture(Offset(at, y));
    // small steps, a finger never skips a tab
    Future<void> to(double x) async {
      while ((x - at).abs() > 5) {
        at += x > at ? 5 : -5;
        await gesture.moveTo(Offset(at, y));
        await tester.pump(const Duration(milliseconds: 16));
      }
      at = x;
      await gesture.moveTo(Offset(at, y));
      await tester.pump(const Duration(milliseconds: 16));
    }

    await to(_pillAt(1.3) + _itemWidth / 2);
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(1.3)), reason: 'the pill sits between tabs mid scrub');
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    expect(selected, isEmpty, reason: 'nothing commits before release');

    await to(_tabCentre(4));
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(4)));
    expect(haptics, hasLength(4));
    await to(_tabCentre(2));
    expect(haptics, hasLength(6));
    expect(haptics.toSet(), {'HapticFeedbackType.selectionClick'});

    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2], reason: 'release commits');
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(2)));
  });

  testWidgets('a tap selects, a vertical drag never scrubs', (tester) async {
    final haptics = _haptics(tester);
    final selected = <int>[];
    await _pumpBar(tester, selected: selected);
    final y = tester.getCenter(find.byType(BackdropFilter)).dy;

    await tester.tapAt(Offset(_tabCentre(3), y));
    await tester.pumpAndSettle();
    expect(selected, [3]);
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(3)));

    await tester.dragFrom(Offset(_tabCentre(1), y), const Offset(4, -200));
    await tester.pumpAndSettle();
    expect(selected, [3]);
    expect(haptics, isEmpty);
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(3)));
  });

  testWidgets('the pill springs to a new tab, and jumps under Reduce Motion', (tester) async {
    await _pumpBar(tester);
    final y = tester.getCenter(find.byType(BackdropFilter)).dy;
    await tester.tapAt(Offset(_tabCentre(3), y));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final mid = _pillLeft(tester);
    expect(mid, greaterThan(_pillAt(0)));
    expect(mid, lessThan(_pillAt(3)), reason: 'the pill slides');
    await tester.pumpAndSettle();
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(3)));
    // critically damped, so it never passes the target
    expect(tester.getRect(find.byKey(const ValueKey('tab-pill'))).left, lessThanOrEqualTo(_pillAt(3) + 0.01));

    // same host, still on tab 3
    await _pumpBar(tester, reduceMotion: true);
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(3)));
    await tester.tapAt(Offset(_tabCentre(1), y));
    await tester.pump();
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(1)), reason: 'Reduce Motion jumps');
  });

  testWidgets('the pill jumps under iOS Reduce Motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpBar(tester);
    final y = tester.getCenter(find.byType(BackdropFilter)).dy;
    await tester.tapAt(Offset(_tabCentre(3), y));
    await tester.pump();
    expect(_pillLeft(tester), moreOrLessEquals(_pillAt(3)));
  });

  testWidgets('each glass tab reads as "Dining, tab 2 of 5" in a tab bar', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpBar(tester);
    final y = tester.getCenter(find.byType(BackdropFilter)).dy;
    await tester.tapAt(Offset(_tabCentre(1), y));
    await tester.pumpAndSettle();

    for (var i = 0; i < _tabs.length; i++) {
      final node = tester.getSemantics(find.bySemanticsLabel('${_tabs[i].label}, tab ${i + 1} of 5'));
      expect(node, isSemantics(isSelected: i == 1, hasSelectedState: true, hasTapAction: true));
      expect(node.getSemanticsData().role, SemanticsRole.tab);
      expect(node.parent!.getSemanticsData().role, SemanticsRole.tabBar);
    }
    semantics.dispose();
  });

  testWidgets('the bar hides while the keyboard is up, and lists lose its inset', (tester) async {
    _phone(tester, const Size(390, 844));
    await _pumpShell(tester);
    await tester.tap(tabLabel('Dining'));
    await tester.pumpAndSettle();
    double inset() => TabBarInset.of(tester.element(find.byType(DiningScreen)));
    expect(inset(), AppTabBar.overlap(tester.element(find.byType(AppTabBar))) + AppTabBar.contentGap);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(AppTabBar), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(inset(), 0);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(AppTabBar), findsOneWidget);
  }, variant: _all);

  testWidgets('minimize on scroll is off by default', (tester) async {
    expect(AppTabBar.minimizeOnScroll, isFalse);
    _phone(tester, const Size(390, 844));
    await _pumpShell(tester);
    await tester.tap(tabLabel('Dining'));
    await tester.pumpAndSettle();
    await tester.drag(find.byWidget(_vertical(tester, find.byType(DiningScreen)).widget), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tabLabel('Dining'), findsOneWidget, reason: 'labels went away with the flag off');
    expect(tester.getRect(find.byType(BackdropFilter)).height, 60);
  }, variant: _ios);

  testWidgets('with the flag on the bar goes icon only scrolling down, back scrolling up', (tester) async {
    _phone(tester, const Size(390, 844));
    await _pumpShell(tester, minimize: true);
    await tester.tap(tabLabel('Dining'));
    await tester.pumpAndSettle();
    Finder list() => find.byWidget(_vertical(tester, find.byType(DiningScreen)).widget);

    await tester.drag(list(), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tabLabel('Dining'), findsNothing);
    expect(tester.getRect(find.byType(BackdropFilter)).height, AppTabBar.minimizedHeight);

    await tester.drag(list(), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(tabLabel('Dining'), findsOneWidget);
  }, variant: _ios);
}
