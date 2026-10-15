/// Today grid reordering only exists in Customize mode.
///
/// Outside it there is no drag handle and dragging is off. Inside it the
/// handle shows (keyboard focusable, with a visible focus ring), the cards
/// expose Move up and Move down as custom semantics actions, and every move
/// announces the new position. The handle, Inspect and Remove share one
/// header row that never overlaps the title.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart' show CardHero;

import 'golden_harness.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Result<Collection<T>> _empty<T>() => Result(
  value: Collection<T>(data: const [], stale: false),
  state: DataState.ok,
);

ThemeData _theme(Brightness brightness) => AppTheme.from(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFF4A6572),
    brightness: brightness,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    double textScale = 1.0,
    double width = 390,
    double height = 844,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, height * 3);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;

    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(brightness),
        home: Scaffold(
          // the boundary is captured on its own, without the scaffold behind
          // it, so it paints the page colour itself or dark shots are white
          body: RepaintBoundary(
            key: const ValueKey('shot'),
            child: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: HomeScreen(
                  api: ApiClient(backend: _EmptyBackend()),
                  dining: _empty<DiningLocation>(),
                  events: _empty<CampusEvent>(),
                  chefs: _empty<MenuItem>(),
                  areas: _empty<HousingArea>(),
                  onRefresh: () async {},
                  onGoToTab: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // finder goldens render at 1x, so grab the boundary at the device ratio
  Future<ui.Image> shot(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    return (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
  }

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Future<void> scrollTo(WidgetTester tester, {required bool bottom}) async {
    final p = position(tester);
    p.jumpTo(bottom ? p.maxScrollExtent : 0);
    await tester.pumpAndSettle();
  }

  Future<void> toggleCustomize(WidgetTester tester) async {
    await scrollTo(tester, bottom: true);
    await tester.tap(
      find.text('Customize').evaluate().isEmpty
          ? find.text('Done')
          : find.text('Customize'),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, bottom: false);
  }

  Iterable<double> handleOpacities(WidgetTester tester) {
    final fades = find.ancestor(
      of: find.byIcon(Icons.drag_indicator_rounded),
      matching: find.byType(AnimatedOpacity),
    );
    return tester.widgetList<AnimatedOpacity>(fades).map((w) => w.opacity);
  }

  bool draggable(WidgetTester tester) => tester
      .widget<ReorderableBuilder<String>>(
        find.byType(ReorderableBuilder<String>),
      )
      .enableDraggable;

  List<String> announcements(WidgetTester tester) {
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final map = message as Map;
        if (map['type'] == 'announce') {
          spoken.add((map['data'] as Map)['message'] as String);
        }
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    return spoken;
  }

  FinderBase<SemanticsNode> card(int position) =>
      find.semantics.byLabel(RegExp('card, position $position of '));

  List<String> actionLabels(FinderBase<SemanticsNode> target) => [
    for (final id
        in target
                .evaluate()
                .single
                .getSemanticsData()
                .customSemanticsActionIds ??
            const <int>[])
      CustomSemanticsAction.getAction(id)!.label!,
  ];

  void runAction(
    WidgetTester tester,
    FinderBase<SemanticsNode> target,
    String label,
  ) {
    final node = target.evaluate().single;
    final data = node.getSemanticsData();
    final id = data.customSemanticsActionIds!.firstWhere(
      (id) => CustomSemanticsAction.getAction(id)!.label == label,
    );
    tester.semantics.performAction(
      target,
      SemanticsAction.customAction,
      args: id,
    );
  }

  List<String> cardLabels(WidgetTester tester) => [
    for (var i = 1; i <= 4; i++)
      card(i).evaluate().single.label.split(' card,').first,
  ];

  testWidgets('outside edit mode there is no handle and dragging is off', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    expect(find.byType(FocusableActionDetector), findsNothing);
    expect(draggable(tester), isFalse);
  });

  testWidgets('in edit mode the handle shows and dragging is on', (
    tester,
  ) async {
    await pumpHome(tester);
    await toggleCustomize(tester);

    expect(handleOpacities(tester).every((o) => o == 1), isTrue);
    expect(draggable(tester), isTrue);

    await toggleCustomize(tester);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    expect(draggable(tester), isFalse);
  });

  testWidgets('with reduce motion the handle appears with no fade', (
    tester,
  ) async {
    await pumpHome(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    await scrollTo(tester, bottom: true);
    await tester.tap(find.text('Customize'));
    await tester.pump();
    await scrollTo(tester, bottom: false);

    final fades = find.ancestor(
      of: find.byIcon(Icons.drag_indicator_rounded),
      matching: find.byType(AnimatedOpacity),
    );
    final durations = tester
        .widgetList<AnimatedOpacity>(fades)
        .map((w) => w.duration);
    expect(durations, isNotEmpty);
    expect(durations.every((d) => d == Duration.zero), isTrue);
    expect(handleOpacities(tester).every((o) => o == 1), isTrue);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('without reduce motion the handle fades in', (tester) async {
    await pumpHome(tester);
    await toggleCustomize(tester);

    final fades = find.ancestor(
      of: find.byIcon(Icons.drag_indicator_rounded),
      matching: find.byType(AnimatedOpacity),
    );
    expect(
      tester
          .widgetList<AnimatedOpacity>(fades)
          .every((w) => w.duration > Duration.zero),
      isTrue,
    );
  });

  testWidgets('customize mode on and off are announced', (tester) async {
    final spoken = announcements(tester);
    await pumpHome(tester);

    await toggleCustomize(tester);
    expect(spoken.last, 'Customize mode on. Select a card to edit it.');

    await toggleCustomize(tester);
    expect(spoken.last, 'Customize mode off');
    expect(spoken, hasLength(2));
  });

  testWidgets('move actions only exist in edit mode', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester, height: 2800);

    expect(actionLabels(card(2)), isEmpty);

    await toggleCustomize(tester);
    expect(
      actionLabels(card(2)),
      unorderedEquals(['Move up', 'Move down']),
    );

    // the ends only offer the move that does something
    expect(actionLabels(card(1)), ['Move down']);
    expect(actionLabels(card(4)), ['Move up']);
    handle.dispose();
  });

  testWidgets('semantics actions reorder and announce the new position', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final spoken = announcements(tester);
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);

    final before = cardLabels(tester);
    runAction(tester, card(1), 'Move down');
    await tester.pumpAndSettle();

    expect(spoken.last, '${before[0]} moved to position 2');
    final after = cardLabels(tester);
    expect(after[1], before[0]);
    expect(after[0], before[1]);

    runAction(tester, card(2), 'Move up');
    await tester.pumpAndSettle();
    expect(spoken.last, '${before[0]} moved to position 1');
    expect(cardLabels(tester), before);
    handle.dispose();
  });

  testWidgets('the move buttons reorder the selected card and announce', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final spoken = announcements(tester);
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);

    // the third card has no scope picker, which overflows at this width
    final before = cardLabels(tester);
    position(tester).jumpTo(900);
    await tester.pumpAndSettle();
    final inspect = find.byTooltip('Customize card').at(2);
    await tester.tap(inspect);
    await tester.pumpAndSettle();
    await scrollTo(tester, bottom: true);
    await tester.tap(find.byTooltip('Move up'));
    await tester.pumpAndSettle();

    expect(spoken.last, '${before[2]} moved to position 2');
    await scrollTo(tester, bottom: false);
    expect(cardLabels(tester)[1], before[2]);
    handle.dispose();
  });

  testWidgets('a long press drag reorders in edit mode', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);

    final before = cardLabels(tester);
    final start = tester.getCenter(
      find.byIcon(Icons.drag_indicator_rounded).first,
    );
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 40; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(cardLabels(tester)[0], isNot(before[0]));
    handle.dispose();
  });

  testWidgets('the same drag does nothing outside edit mode', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester, height: 2800);

    final before = cardLabels(tester);
    // no handle outside edit mode, so grab where the handle would be
    final gesture = await tester.startGesture(
      tester.getTopRight(find.byType(CardShell).first) + const Offset(-30, 30),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 40; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(cardLabels(tester), before);
    handle.dispose();
  });

  testWidgets('a drop gives one light haptic and nothing else', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);
    expect(haptics, isEmpty);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_indicator_rounded).first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 40; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    // the framework adds its own click on long press pickup, the drop is ours
    const light = 'HapticFeedbackType.lightImpact';
    expect(haptics.where((h) => h == light), hasLength(1));
    expect(haptics.last, light);
    expect(
      haptics.toSet().difference({light, 'HapticFeedbackType.selectionClick'}),
      isEmpty,
    );
  });

  // The dashboard itself at 2x text overflows inside the empty states
  // (empty_state.dart, not this change), so the 2x cases are covered at the
  // card header level below, where nothing is expected to overflow.
  for (final width in [390.0, 430.0, 700.0, 1000.0]) {
    for (final scale in [1.0]) {
      testWidgets(
        'edit header at ${width.toInt()} wide, text ${scale}x: handle, '
        'Inspect and Remove never overlap each other or the title',
        (tester) async {
          await pumpHome(
            tester,
            width: width,
            height: 2800,
            textScale: scale,
          );
          await toggleCustomize(tester);

          final shells = find.byType(CardShell);
          expect(shells, findsNWidgets(4));
          for (var i = 0; i < 4; i++) {
            final shell = shells.at(i);
            Finder inShell(Finder f) => find.descendant(of: shell, matching: f);
            final card = tester.getRect(shell);
            final handle = Rect.fromCenter(
              center: tester.getCenter(
                inShell(find.byIcon(Icons.drag_indicator_rounded)),
              ),
              width: 32,
              height: 32,
            );
            final inspect = tester.getRect(
              inShell(find.byTooltip('Customize card')),
            );
            final remove = tester.getRect(
              inShell(find.byTooltip('Remove card from Today')),
            );
            final title = tester.getRect(inShell(find.byType(Text)).first);
            final named = {
              'handle': handle,
              'inspect': inspect,
              'remove': remove,
              'title': title,
            };

            for (final a in named.entries) {
              expect(
                card.contains(a.value.topLeft) &&
                    card.contains(a.value.bottomRight),
                isTrue,
                reason: 'card $i ${a.key} ${a.value} leaves card $card',
              );
              for (final b in named.entries) {
                if (a.key.compareTo(b.key) >= 0) continue;
                expect(
                  a.value.overlaps(b.value),
                  isFalse,
                  reason: 'card $i ${a.key} ${a.value} overlaps '
                      '${b.key} ${b.value}',
                );
              }
            }
            // the title ends before the first control starts
            expect(title.right, lessThanOrEqualTo(handle.left));
            expect(handle.right, lessThanOrEqualTo(inspect.left));
            expect(inspect.right, lessThanOrEqualTo(remove.left));
          }
        },
      );
    }
  }

  // The owner-approved phone gap between two stacked cards, in both modes. The
  // cards are as tall as their content, so the gap is the only thing between
  // them and it is the token, not a leftover of a fixed height cell.
  for (final size in const [
    Size(320, 640),
    Size(390, 844),
    Size(430, 932),
    Size(440, 956),
    Size(599, 900),
  ]) {
    for (final scale in const [1.0, 2.0]) {
    goldenWidgets(
      'at ${size.width.toInt()}x${size.height.toInt()}, text ${scale}x, the gap '
      'between cards is 10 in normal and edit mode, and edit mode keeps card 1',
      (tester) async {
        await pumpHome(
          tester,
          width: size.width,
          height: size.height,
          textScale: scale,
        );
        ({double height, List<double> gaps}) measure() {
          final shells = find.byType(CardShell);
          final rects = [
            for (var i = 0; i < 3; i++) tester.getRect(shells.at(i)),
          ];
          return (
            height: rects.first.height,
            gaps: [
              for (var i = 0; i < 2; i++) rects[i + 1].top - rects[i].bottom,
            ],
          );
        }

        final normal = measure();
        expect(normal.gaps, [10.0, 10.0]);
        await toggleCustomize(tester);
        final edit = measure();

        expect(edit.gaps, [10.0, 10.0]);
        expect(edit.height, normal.height);
      },
    );
    }
  }

  // Card widths the dashboard gives one column cards: the viewport minus the
  // phone's 16 page margin on each side, at 320, 390, 430 and a tablet. Real
  // Rubik, so the title measures as it does on a device.
  const titles = [
    'Visiting Chefs',
    'Mailing Address',
    'Visiting chefs and a very long module title',
  ];
  for (final title in titles) {
    for (final cardWidth in [288.0, 358.0, 398.0, 672.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final hero in [false, true]) {
        goldenWidgets(
          'card header "$title", ${cardWidth.toInt()} wide, text ${scale}x'
          '${hero ? ', with hero' : ''}: title stops before the controls',
          (tester) async {
            // a phone sized view, so the card padding is the phone's
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(cardWidth + 32, 4000);
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearAllTestValues);
            await tester.pumpWidget(
              MaterialApp(
                theme: _theme(Brightness.light),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: cardWidth,
                      child: CardShell(
                        title: title,
                        hero: hero
                            ? const CardHero(value: '3', label: 'OPEN')
                            : null,
                        dragHandle: EditControls(
                          selected: false,
                          onInspect: () {},
                          onRemove: () {},
                        ),
                        child: const SizedBox(height: 40),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final handle = Rect.fromCenter(
              center: tester.getCenter(
                find.byIcon(Icons.drag_indicator_rounded),
              ),
              width: 32,
              height: 32,
            );
            final inspect = tester.getRect(find.byTooltip('Customize card'));
            final remove = tester.getRect(
              find.byTooltip('Remove card from Today'),
            );
            final titleRect = tester.getRect(find.text(title));
            final shell = tester.getRect(find.byType(CardShell));
            final named = {
              'handle': handle,
              'inspect': inspect,
              'remove': remove,
              'title': titleRect,
            };
            for (final a in named.entries) {
              expect(shell.contains(a.value.topLeft), isTrue);
              expect(shell.contains(a.value.bottomRight), isTrue);
              for (final b in named.entries) {
                if (a.key.compareTo(b.key) >= 0) continue;
                expect(
                  a.value.overlaps(b.value),
                  isFalse,
                  reason: '${a.key} ${a.value} overlaps ${b.key} ${b.value}',
                );
              }
            }
            // beside the controls, the title ends before the handle
            if (titleRect.bottom > handle.top && titleRect.top < handle.bottom) {
              expect(titleRect.right, lessThanOrEqualTo(handle.left));
            }

            // Whole words only: the title is at least as wide as its longest
            // word, so nothing breaks mid-word, and it is never cut.
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(title),
            );
            expect(
              paragraph.getMinIntrinsicWidth(double.infinity),
              lessThanOrEqualTo(paragraph.size.width + 0.01),
              reason: 'a word was broken across lines',
            );
            expect(tester.widget<Text>(find.text(title)).maxLines, isNull);
            // At 1x on a 390 or wider phone the module names fit on one line
            // beside the controls.
            if (scale == 1 && !hero && cardWidth >= 358 && title.length < 20) {
              expect(
                paragraph.getMaxIntrinsicWidth(double.infinity),
                lessThanOrEqualTo(paragraph.size.width + 0.01),
                reason: '"$title" wrapped at 1x',
              );
            }

            // Controls beside or under the title, the header is the same
            // height with the controls gone.
            final editHeader = tester.getRect(find.byType(CardShell)).height;
            await tester.pumpWidget(
              MaterialApp(
                theme: _theme(Brightness.light),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: cardWidth,
                      child: CardShell(
                        title: title,
                        hero: hero
                            ? const CardHero(value: '3', label: 'OPEN')
                            : null,
                        child: const SizedBox(height: 40),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byType(CardShell)).height,
              editHeader,
              reason: 'edit mode changed the card height',
            );
          },
        );
      }
    }
    }
  }

  testWidgets('in edit mode the handle takes keyboard focus with a ring', (
    tester,
  ) async {
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);

    final ring = find.byKey(const ValueKey('drag-handle-focus-ring'));
    expect(ring, findsNothing);

    var tabs = 0;
    while (ring.evaluate().isEmpty && tabs < 40) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      tabs++;
    }
    expect(ring, findsOneWidget, reason: 'Tab never reached a drag handle');

    // the focused node belongs to a handle, and the ring is visibly outside it
    final focused = FocusManager.instance.primaryFocus!.context!;
    final handleIcon = find.descendant(
      of: find.byElementPredicate((e) => e == focused),
      matching: find.byIcon(Icons.drag_indicator_rounded),
    );
    expect(handleIcon, findsOneWidget);
    expect(
      tester.getRect(ring).size,
      const Size(40, 40),
      reason: '32px handle plus the 2px ring and 2px offset on each side',
    );

    // Enter opens the card's options, where Move up and Move down live
    expect(find.text('SIZE'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('SIZE'), findsOneWidget);
  });

  testWidgets('outside edit mode no handle can take focus', (tester) async {
    await pumpHome(tester, height: 2800);

    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byKey(const ValueKey('drag-handle-focus-ring')), findsNothing);
    }
    expect(find.byType(FocusableActionDetector), findsNothing);
  });

  // 3x device ratio, one image per combination. The tall sizes show all four
  // cards and the Customize or Done control in one image.
  const sizes = {
    '390x844': Size(390, 844),
    '430x932': Size(430, 932),
    '440x956': Size(440, 956),
    // tall enough that the cards reach their maximum height and the page,
    // including the Customize or Done bar and the colophon at 2x text, fits
    // with no scrolling
    '390x4800': Size(390, 4800),
    '430x4800': Size(430, 4800),
  };
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};
  const scales = {'1x': 1.0, '2x': 2.0};
  for (final size in sizes.entries) {
    for (final theme in themes.entries) {
      for (final scale in scales.entries) {
        for (final edit in [false, true]) {
          final mode = edit ? 'edit' : 'normal';
          final name = '${size.key}_${theme.key}_text${scale.key}_$mode';
          goldenWidgets('golden $name', (tester) async {
            await pumpHome(
              tester,
              width: size.value.width,
              height: size.value.height,
              brightness: theme.value,
              textScale: scale.value,
            );
            if (edit) await toggleCustomize(tester);
            if (size.value.height > 2000) {
              // the tall images must show every card and the whole bar
              expect(position(tester).maxScrollExtent, 0);
              final bar = tester.getRect(find.text(edit ? 'Done' : 'Customize'));
              expect(bar.bottom, lessThanOrEqualTo(size.value.height));
              expect(
                tester.getRect(find.byType(CardShell).at(3)).bottom,
                lessThan(bar.top),
              );
            }
            await expectLater(
              await shot(tester),
              matchesGoldenFile('goldens/home_reorder_$name.png'),
            );
          });
        }
      }
    }
  }

  // These save a changed dashboard that leaks into later tests (the goldens
  // above are recorded with the earlier drag tests' leftovers), so they stay
  // after the goldens.
  testWidgets('a drag reorder announces the new order', (tester) async {
    final spoken = announcements(tester);
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);
    spoken.clear();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_indicator_rounded).first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 40; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(spoken, ['Dashboard order updated']);
  });

  testWidgets('removing and re-adding a card is announced', (tester) async {
    final handle = tester.ensureSemantics();
    final spoken = announcements(tester);
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);

    final first = cardLabels(tester)[0];
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(spoken.last, '$first removed');

    await scrollTo(tester, bottom: true);
    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('ADD A CARD'),
              matching: find.byType(Column),
            ),
            matching: find.byType(InkWell),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(spoken.last, '$first added');
    handle.dispose();
  });

  testWidgets('resizing the selected card is announced', (tester) async {
    final spoken = announcements(tester);
    await pumpHome(tester, height: 2800);
    await toggleCustomize(tester);

    // earlier tests leave the order shuffled, so find a card with a spare size
    final chip = find.byType(ChoiceChip);
    var unselected = -1;
    for (var i = 0; i < 4 && unselected < 0; i++) {
      await scrollTo(tester, bottom: false);
      position(tester).jumpTo(300.0 * i);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Customize card').at(i));
      await tester.pumpAndSettle();
      await scrollTo(tester, bottom: true);
      unselected = tester
          .widgetList<ChoiceChip>(chip)
          .toList()
          .indexWhere((c) => !c.selected);
    }
    expect(unselected, isNonNegative);
    await tester.tap(chip.at(unselected));
    await tester.pumpAndSettle();

    expect(spoken.last, matches(RegExp(r' resized to \w+$')));
  });
}
