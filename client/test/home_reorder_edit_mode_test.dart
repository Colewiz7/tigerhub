/// Today grid reordering only exists in Customize mode.
///
/// Outside it the drag handle is hidden and dragging is off. Inside it the
/// handle shows, the cards expose move earlier/later as custom semantics
/// actions, and every move announces the new position.
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
          body: RepaintBoundary(
            key: const ValueKey('shot'),
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

  testWidgets('outside edit mode the handle is hidden and dragging is off', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(handleOpacities(tester), isNotEmpty);
    expect(handleOpacities(tester).every((o) => o == 0), isTrue);
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
    expect(handleOpacities(tester).every((o) => o == 0), isTrue);
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
      unorderedEquals(['Move earlier', 'Move later']),
    );

    // the ends only offer the move that does something
    expect(actionLabels(card(1)), ['Move later']);
    expect(actionLabels(card(4)), ['Move earlier']);
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
    runAction(tester, card(1), 'Move later');
    await tester.pumpAndSettle();

    expect(spoken.last, '${before[0]} moved to position 2');
    final after = cardLabels(tester);
    expect(after[1], before[0]);
    expect(after[0], before[1]);

    runAction(tester, card(2), 'Move earlier');
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
    await tester.tap(find.byTooltip('Move earlier'));
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

  // 3x device ratio, one image per combination
  const sizes = {'390x844': Size(390, 844), '430x932': Size(430, 932)};
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};
  const scales = {'1x': 1.0, '2x': 2.0};
  for (final size in sizes.entries) {
    for (final theme in themes.entries) {
      for (final scale in scales.entries) {
        for (final edit in [false, true]) {
          final mode = edit ? 'edit' : 'normal';
          final name = '${size.key}_${theme.key}_text${scale.key}_$mode';
          testWidgets('golden $name', (tester) async {
            // empty_state.dart overflows at 2x text, so keep going and say so
            final overflows = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              if (details.exceptionAsString().contains('overflowed')) {
                overflows.add(details.exceptionAsString().split('\n').first);
                return;
              }
              previous?.call(details);
            };
            addTearDown(() => FlutterError.onError = previous);
            await pumpHome(
              tester,
              width: size.value.width,
              height: size.value.height,
              brightness: theme.value,
              textScale: scale.value,
            );
            if (edit) await toggleCustomize(tester);
            await expectLater(
              await shot(tester),
              matchesGoldenFile('goldens/home_reorder_$name.png'),
            );
            if (overflows.isNotEmpty) {
              debugPrint('OVERFLOW $name: ${overflows.toSet()}');
            }
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
