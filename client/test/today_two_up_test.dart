/// Two compact cards share a row on a phone, until the text gets large or the
/// phone gets narrow.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/compact_card.dart';

import 'golden_harness.dart';

class _Backend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/recreation/hours') return jsonDecode(File('test/golden/recreation_hours.json').readAsStringSync()) as Map<String, dynamic>;
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

const _chefs = [MenuItem(id: 1, locationName: 'RITZ', name: 'Chef A'), MenuItem(id: 2, locationName: 'Gracies', name: 'Chef B')];

const _dining = CardInstance(id: 'dining-0', type: ModuleType.diningStatus);
const _chefsCompact = CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs, size: CardSize.compact);
const _pool = CardInstance(id: 'facility-0', type: ModuleType.facilityHours, size: CardSize.compact, scope: 'Judson/Hale Aquatics Center');
const _gym = CardInstance(id: 'facility-1', type: ModuleType.facilityHours, size: CardSize.compact, scope: 'Wiedman Fitness Center');

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    // sun aug 30 2026, noon on campus, the day the fixture covers
    RitClock.pin(DateTime.utc(2026, 8, 30, 16));
  });
  tearDown(RitClock.reset);

  Future<void> pumpToday(WidgetTester tester, List<CardInstance> cards, {double width = 390, double scale = 1, Brightness brightness = Brightness.light, double ratio = 1}) async {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(width, 1400) * ratio;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await DashboardStore.save(cards);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness)),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: HomeScreen(
            api: ApiClient(backend: _Backend()),
            dining: _ok<DiningLocation>(const [DiningLocation(id: 1, name: 'Crossroads', isOpen: true)]),
            events: _ok<CampusEvent>(const []),
            chefs: _ok(_chefs),
            areas: _ok<HousingArea>(const []),
            onRefresh: () async {},
            onGoToTab: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect compact(WidgetTester tester, int index) => tester.getRect(find.byType(CompactCard).at(index));

  group('pairing', () {
    test('neighbours pair, a third compact card stays alone', () {
      expect(phonePairs([_dining, _chefsCompact, _pool, _gym]), {1, 2});
      expect(phonePairs([_chefsCompact, _dining, _pool]), isEmpty);
      expect(phonePairs([_chefsCompact, _pool, _gym, _chefsCompact]), {0, 1, 2, 3});
    });

    test('a compact dining or events card is not a half card', () {
      const diningCompact = CardInstance(id: 'd', type: ModuleType.diningStatus, size: CardSize.compact);
      expect(phonePairs([diningCompact, _pool]), isEmpty);
    });

    test('two up needs 360 wide and text no larger than 1.35', () {
      expect(phoneTwoUp(width: 390, textScale: 1), isTrue);
      expect(phoneTwoUp(width: 360, textScale: 1.35), isTrue);
      expect(phoneTwoUp(width: 359, textScale: 1), isFalse);
      expect(phoneTwoUp(width: 390, textScale: 1.4), isFalse);
    });
  });

  testWidgets('at 390 two compact cards share a row, 174 wide each, the same height', (tester) async {
    await pumpToday(tester, [_dining, _chefsCompact, _pool]);
    final a = compact(tester, 0);
    final b = compact(tester, 1);
    expect(a.top, b.top);
    expect(a.width, 174);
    expect(b.width, 174);
    expect(a.height, b.height);
    expect(a.left, 16);
    expect(b.left - a.right, 10);
    expect(find.text('Pool'), findsOneWidget);
    expect(find.text('Opens 2:30 PM'), findsOneWidget);
  });

  testWidgets('at 1.4x text they stack full width', (tester) async {
    await pumpToday(tester, [_dining, _chefsCompact, _pool], scale: 1.4);
    expect(compact(tester, 1).top, greaterThan(compact(tester, 0).bottom));
    expect(compact(tester, 0).width, 358);
  });

  testWidgets('at 320 wide they stack full width', (tester) async {
    await pumpToday(tester, [_dining, _chefsCompact, _pool], width: 320);
    expect(compact(tester, 1).top, greaterThan(compact(tester, 0).bottom));
    expect(compact(tester, 0).width, 288);
  });

  testWidgets('a compact card on its own is full width', (tester) async {
    await pumpToday(tester, [_chefsCompact, _dining]);
    expect(compact(tester, 0).width, 358);
  });

  testWidgets('screen readers keep the saved order', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpToday(tester, [_dining, _chefsCompact, _pool, _gym]);
    final keys = [
      for (final element in find.byWidgetPredicate((w) => w is Semantics && w.key is ValueKey<String> && w.properties.sortKey is OrdinalSortKey).evaluate())
        ((element.widget as Semantics).properties.sortKey! as OrdinalSortKey).order,
    ];
    expect(keys, [0, 1, 2, 3]);
    handle.dispose();
  });

  testWidgets('moving a card down re-pairs by the new order', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpToday(tester, [_chefsCompact, _dining, _pool]);
    expect(compact(tester, 0).width, 358);
    await tester.scrollUntilVisible(find.text('Customize'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    final dining = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Dining|^Eat now')).first);
    dining.owner!.performAction(dining.id, SemanticsAction.customAction, CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Move down')));
    await tester.pumpAndSettle();
    expect(compact(tester, 0).top, compact(tester, 1).top);
    handle.dispose();
  });

  for (final brightness in Brightness.values) {
    for (final edit in [false, true]) {
      final shot = 'today_two_up_390_${brightness.name}${edit ? '_edit' : ''}';
      goldenWidgets('golden $shot', (tester) async {
        await pumpToday(tester, [_dining, _chefsCompact, _pool], brightness: brightness, ratio: 3);
        if (edit) {
          await tester.scrollUntilVisible(find.text('Customize'), 300, scrollable: find.byType(Scrollable).first);
          await tester.tap(find.text('Customize'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.byType(CompactCard).first, -300, scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final image = (await tester.runAsync<ui.Image>(() => boundary.toImage(pixelRatio: 3)))!;
        await expectLater(image, matchesGoldenFile('goldens/$shot.png'));
      });
    }
  }
}
