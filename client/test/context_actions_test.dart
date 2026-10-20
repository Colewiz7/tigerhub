/// The ContextActions wrapper on its own: scope, keyboard, motion, scrolling, taps.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/tokens.dart';
import 'package:tigerhub/widgets/context_actions.dart';
import 'package:tigerhub/widgets/phone_frame.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'support/context_menu_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var taps = 0;
  var picked = 0;

  setUp(() {
    taps = 0;
    picked = 0;
  });

  Widget app({bool enabled = true, bool reduceMotion = false, Widget? body}) => MaterialApp(
    theme: menuTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(
      body: ContextActionsScope(
        enabled: enabled,
        child:
            body ??
            ListView(
              children: [
                StatusRow(
                  icon: Icons.event_rounded,
                  title: 'Row',
                  subtitle: 'Sub',
                  onTap: () => taps++,
                  actions: [
                    MenuAction(
                      label: 'Pick',
                      icon: Icons.check_rounded,
                      onSelected: (_) => picked++,
                    ),
                  ],
                ),
                for (var i = 0; i < 30; i++) StatusRow(icon: Icons.event_rounded, title: 'Filler $i'),
              ],
            ),
      ),
    ),
  );

  Finder row() => find.text('Row');

  Future<void> allThreeInputs(WidgetTester tester, {required bool opens}) async {
    await secondaryTap(tester, row());
    expect(menuItems, opens ? findsOneWidget : findsNothing, reason: 'secondary tap');
    if (opens) await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await longPress(tester, row());
    expect(menuItems, opens ? findsOneWidget : findsNothing, reason: 'long press');
    if (opens) await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await keyboardOpen(tester, row());
    expect(menuItems, opens ? findsOneWidget : findsNothing, reason: 'context menu key');
    if (opens) await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await keyboardOpen(tester, row(), shiftF10: true);
    expect(menuItems, opens ? findsOneWidget : findsNothing, reason: 'shift f10');
    if (opens) await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  testWidgets('does not open when the scope is disabled, opens when enabled', (tester) async {
    MenuProbe().install(tester);
    await tester.pumpWidget(app(enabled: false));
    await allThreeInputs(tester, opens: false);

    final semantics = tester.ensureSemantics();
    await tester.pump();
    final wrapper = find.byType(ContextActions).first;
    expect(tester.getSemantics(wrapper).getSemanticsData().customSemanticsActionIds ?? const [], isEmpty);

    await tester.pumpWidget(app(enabled: true));
    await tester.pumpAndSettle();
    await allThreeInputs(tester, opens: true);
    expect(tester.getSemantics(wrapper).getSemanticsData().customSemanticsActionIds, hasLength(1));

    await tester.pumpWidget(app(enabled: false));
    await tester.pumpAndSettle();
    await allThreeInputs(tester, opens: false);
    semantics.dispose();
  });

  testWidgets('no scope at all means enabled', (tester) async {
    MenuProbe().install(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: menuTheme(),
        home: Scaffold(
          body: StatusRow(
            icon: Icons.event_rounded,
            title: 'Row',
            onTap: () {},
            actions: [MenuAction(label: 'Pick', icon: Icons.check_rounded, onSelected: (_) {})],
          ),
        ),
      ),
    );
    await secondaryTap(tester, row());
    expect(menuItems, findsOneWidget);
  });

  testWidgets('a row with no actions has no menu', (tester) async {
    MenuProbe().install(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: menuTheme(),
        home: const Scaffold(body: StatusRow(icon: Icons.event_rounded, title: 'Row')),
      ),
    );
    await secondaryTap(tester, row());
    await longPress(tester, row());
    expect(menuItems, findsNothing);
  });

  testWidgets('picking an item runs its action once', (tester) async {
    MenuProbe().install(tester);
    await tester.pumpWidget(app());
    await secondaryTap(tester, row());
    await tapMenuItem(tester, 'Pick');
    expect(picked, 1);
  });

  testWidgets('menu is flat: no shadow, no blur, inner radius, 48px items', (tester) async {
    MenuProbe().install(tester);
    await tester.pumpWidget(app());
    await secondaryTap(tester, row());

    final material = tester.widget<Material>(find.ancestor(of: menuItems.first, matching: find.byType(Material)).first);
    expect(material.elevation, 0);
    expect(material.shadowColor, Colors.transparent);
    expect((material.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(20));
    expect(material.color, menuTheme().colorScheme.surfaceContainerHighest);
    expect(find.byType(BackdropFilter), findsNothing);
    await expectMenuOpen(tester, ['Pick']);
  });

  testWidgets('reduce motion makes the route zero duration, otherwise it animates', (tester) async {
    MenuProbe().install(tester);
    await tester.pumpWidget(app(reduceMotion: true));
    await secondaryTap(tester, row());
    expect(ModalRoute.of(tester.element(menuItems))!.transitionDuration, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.pumpWidget(app());
    await secondaryTap(tester, row());
    expect(ModalRoute.of(tester.element(menuItems))!.transitionDuration, greaterThan(Duration.zero));
  });

  testWidgets('in a centered phone frame the popup stays inside the frame', (tester) async {
    MenuProbe().install(tester);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: menuTheme(),
        builder: phoneModeBuilder(const PhoneMode()),
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                StatusRow(
                  icon: Icons.event_rounded,
                  title: 'Row $i',
                  actions: [
                    MenuAction(label: 'Pick', icon: Icons.check_rounded, onSelected: (_) {}),
                    MenuAction(label: 'Pick something longer', icon: Icons.check_rounded, onSelected: (_) {}),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final frame = tester.getRect(find.byType(SizedBox).first);
    final phone = Rect.fromCenter(center: const Offset(500, 500), width: 390, height: 844);
    expect(frame.size, phone.size);
    const inset = 4.0;
    final taps = {
      'left': Offset(phone.left + inset, phone.top + 100),
      'right': Offset(phone.right - inset, phone.top + 100),
      'top': Offset(phone.center.dx, phone.top + inset),
      'bottom': Offset(phone.center.dx, phone.bottom - inset),
      'bottom right': Offset(phone.right - inset, phone.bottom - inset),
    };
    for (final MapEntry(:key, :value) in taps.entries) {
      final gesture = await tester.startGesture(value, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.ancestor(of: menuItems.first, matching: find.byType(Material)).first);
      expect(phone.contains(menu.topLeft) && phone.contains(menu.bottomRight), isTrue, reason: '$key tap: menu $menu leaves the frame $phone');
      expect(menu.inflate(8).contains(value), isTrue, reason: '$key tap: menu $menu is not anchored at $value');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the keyboard focus ring sits 2px clear of the row', (tester) async {
    MenuProbe().install(tester);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await tester.pumpWidget(
      MaterialApp(
        theme: menuTheme(),
        home: Scaffold(
          body: Center(
            child: ContextActions(
              focusable: true,
              actions: [MenuAction(label: 'Pick', icon: Icons.check_rounded, onSelected: (_) {})],
              child: const SizedBox(width: 200, height: 64, child: Text('Row')),
            ),
          ),
        ),
      ),
    );
    final row = tester.getRect(find.text('Row'));
    expect(find.byKey(ContextActions.ringKey), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(ContextActions.ringKey)), row.inflate(4));
    final ring = tester.widget<DecoratedBox>(find.byKey(ContextActions.ringKey));
    // outer edge = 20 row + 2 gap + 2 stroke; the stroke paints inward, so the
    // inner edge lands 2px off the row (22) and the centerline at 23
    expect((ring.decoration as BoxDecoration).borderRadius, BorderRadius.circular(24));
    expect(ContextActions.ringOuterRadius, Shapes.innerRadius + ContextActions.ringGap + ContextActions.ringWidth);
  });

  testWidgets('long press does not hijack a vertical scroll, and taps still land', (tester) async {
    final probe = MenuProbe()..install(tester);
    await tester.pumpWidget(app());
    final list = find.byType(ListView);

    await tester.drag(row(), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position.pixels, greaterThan(0));
    expect(menuItems, findsNothing);

    // held then dragged: the scroll wins once the finger moves
    await tester.fling(find.text('Filler 5'), const Offset(0, 200), 1000);
    await tester.pumpAndSettle();
    expect(menuItems, findsNothing);
    expect(probe.haptics, isEmpty);

    await tester.drag(list, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.tap(row());
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(menuItems, findsNothing);
  });
}
