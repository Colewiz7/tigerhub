/// Today on an Android phone at the text sizes Android users actually run
/// (1.15 and 1.3 are the stops either side of default in Display size and
/// text). The first pass only checked 1.0 and 2.0 and missed a dead band
/// under the Eat now and Up next headers at the sizes in between.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/events_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/compact_card.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart' show CardHero;
import 'package:tigerhub/widgets/status_row.dart';
import 'package:tigerhub/widgets/today_header.dart';

import 'golden_harness.dart' show loadGoldenFonts;

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => path == '/makerspace/hours'
      ? {'items': <dynamic>[]}
      : {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(
  value: Collection<T>(data: data, stale: false),
  state: DataState.ok,
);

// wed oct 14 2026 on campus, edt so utc is 4 hours ahead
DateTime _at(int hour) => DateTime.utc(2026, 10, 14, hour + 4);

const _saved = [
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(
    id: 'shuttles-0',
    type: ModuleType.shuttles,
    size: CardSize.compact,
  ),
  CardInstance(
    id: 'package-0',
    type: ModuleType.packagePickup,
    size: CardSize.compact,
  ),
  CardInstance(
    id: 'fac-0',
    type: ModuleType.facilityHours,
    size: CardSize.compact,
  ),
  CardInstance(
    id: 'chefs-0',
    type: ModuleType.visitingChefs,
    size: CardSize.compact,
  ),
  CardInstance(id: 'map-0', type: ModuleType.campusMap),
  CardInstance(id: 'housing-0', type: ModuleType.mailingAddress),
];

void main() {
  setUpAll(loadGoldenFonts);
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    RitClock.pin(_at(12));
  });
  tearDown(RitClock.reset);

  Future<ScrollPosition> pumpToday(
    WidgetTester tester,
    Size size,
    double scale,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 48);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await DashboardStore.save(_saved);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: HomeScreen(
            api: ApiClient(backend: _EmptyBackend()),
            dining: _ok([
              DiningLocation(id: 1, name: 'Beanz', isOpen: true),
              DiningLocation(id: 2, name: 'Market', isOpen: true),
              DiningLocation(id: 3, name: 'Midnight Oil', isOpen: true),
            ]),
            events: _ok([
              CampusEvent(
                uid: 'a',
                source: 't',
                title: 'Soccer',
                startsAt: _at(13),
                endsAt: _at(14),
                organizer: 'X',
                organizerKey: 'x',
              ),
              CampusEvent(
                uid: 'b',
                source: 't',
                title: 'Chess',
                startsAt: _at(14),
                endsAt: _at(15),
                organizer: 'X',
                organizerKey: 'x',
              ),
            ]),
            chefs: _ok<MenuItem>(const []),
            areas: _ok<HousingArea>(const []),
            onRefresh: () async {},
            onGoToTab: (_) {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
  }

  // the platform override must be gone before the test's invariants run
  void androidTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final scale in const [1.0, 1.15, 1.3, 2.0]) {
      for (final scrolled in const [false, true]) {
        final name =
            '${size.width.toInt()} wide ${scale}x text ${scrolled ? 'scrolled' : 'unscrolled'}';

        // At 2.0x the title wraps to three lines and the controls can only go
        // under it, so the band keeps the 38 that edit mode may grow it by
        // (_editGrowth). That is by design and the same on main, so no test.
        if (scale < 2) {
          androidTest(
            '$name: no dead band between a card header and its first row',
            (tester) async {
              final position = await pumpToday(tester, size, scale);
              if (scrolled) {
                position.jumpTo(120);
                await tester.pump(const Duration(milliseconds: 300));
              }
              for (final (type, title) in [
                (DiningCard, 'Eat now'),
                (EventsCard, 'Up next'),
              ]) {
                final card = find.byType(type);
                final titleRect = tester.getRect(
                  find.descendant(of: card, matching: find.text(title)),
                );
                final firstRow = tester.getRect(
                  find
                      .descendant(of: card, matching: find.byType(StatusRow))
                      .first,
                );
                // a hero pill sits beside the title and may be the taller of the two
                final hero = tester.getRect(
                  find.descendant(of: card, matching: find.byType(CardHero)),
                );
                final headerBottom = titleRect.bottom > hero.bottom
                    ? titleRect.bottom
                    : hero.bottom;
                // 8 under the band, a few points of text leading around the title
                expect(
                  firstRow.top - headerBottom,
                  lessThan(16),
                  reason:
                      '$title: header ends ${headerBottom.toStringAsFixed(1)}, first row starts ${firstRow.top.toStringAsFixed(1)}',
                );
              }
            },
          );
        }

        androidTest(
          '$name: Today cards stay in their cells, clear of each other and under the collapsed bar',
          (tester) async {
            final position = await pumpToday(tester, size, scale);
            final headerHeight = tester
                .getSize(find.byType(TodayHeader))
                .height;
            for (final offset
                in scrolled ? const [60.0, 200.0, 400.0, 900.0] : const [0.0]) {
              position.jumpTo(offset.clamp(0, position.maxScrollExtent));
              await tester.pump(const Duration(milliseconds: 300));
              final rects = [
                for (final type in [CompactCard, CardShell])
                  for (final element in find.byType(type).evaluate())
                    tester.getRect(find.byWidget(element.widget)),
              ];
              for (final (i, a) in rects.indexed) {
                expect(a.left, greaterThanOrEqualTo(0));
                expect(a.right, lessThanOrEqualTo(size.width));
                for (final b in rects.skip(i + 1)) {
                  expect(
                    a.overlaps(b),
                    isFalse,
                    reason: '$a overlaps $b at scroll $offset',
                  );
                }
              }
              // the bar comes in once the large date has scrolled away
              final collapsed = position.pixels >= headerHeight - 8 + 1;
              if (collapsed) {
                final bar = find.byType(TodayCollapsedBar);
                expect(bar, findsOneWidget);
                await tester.pump(const Duration(milliseconds: 300));
                final barObject = tester.renderObject(bar);
                final barBox = tester.getRect(bar);
                // the first thing hit under a point in the bar is the bar, never a card
                final top = tester
                    .hitTestOnBinding(Offset(size.width / 2, barBox.center.dy))
                    .path
                    .map((e) => e.target)
                    .whereType<RenderObject>()
                    .first;
                RenderObject? up = top;
                while (up != null && up != barObject) {
                  up = up.parent;
                }
                expect(
                  up,
                  same(barObject),
                  reason: 'at scroll $offset the first hit in the bar is $top',
                );
              }
            }
          },
        );
      }
    }
  }
}
