/// The ContextActions wrapper on its own: scope, keyboard, motion, scrolling, taps.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/context_actions.dart';
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
