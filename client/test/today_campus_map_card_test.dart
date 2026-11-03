/// The Campus map card on Today, on an Android phone, with places loaded.
///
/// Reported from a device: two half width cards painted over the collapsed date
/// bar and over the cards around them, from launch, and the page had a blank
/// stretch at its end where they belonged. The map is a Column with an
/// Expanded, and a phone card has no height to hand it, so the layout threw
/// ("RenderFlex children have non-zero flex but incoming height constraints are
/// unbounded"). Debug shows that; release carries on with an unlaid out card
/// and everything after it lands in the wrong place. Tests that never loaded
/// any places never built the part that fails.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/compact_card.dart';
import 'package:tigerhub/widgets/today_header.dart';

import 'golden_harness.dart' show loadGoldenFonts;

/// Answers the map endpoint with a few places and everything else empty.
class _MapBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    if (path == '/campus/map') {
      return {
        'data': [
          for (var i = 0; i < 12; i++)
            {
              'id': i,
              'kind': i.isEven ? 'entrance_accessible' : 'atm',
              'kind_name': i.isEven ? 'Accessible entrances' : 'ATMs',
              'name': 'Place $i',
              'geometry': {
                'type': 'Point',
                'coordinates': [-77.68 + i * 0.001, 43.08 + i * 0.001],
              },
            },
        ],
        'stale': false,
        'last_updated': null,
      };
    }
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(
  value: Collection<T>(data: data, stale: false),
  state: DataState.ok,
);

const _saved = [
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'map-0', type: ModuleType.campusMap),
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
  CardInstance(id: 'academic-0', type: ModuleType.academicDates),
];

void main() {
  setUpAll(loadGoldenFonts);
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });
  tearDown(RitClock.reset);

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final scale in const [1.0, 1.15, 1.3, 2.0]) {
      for (final scrolled in const [false, true]) {
        final name =
            '${size.width.toInt()} wide ${scale}x text ${scrolled ? 'scrolled' : 'unscrolled'}';

        testWidgets(
          '$name: the map card lays out and the cards after it stay in place',
          (tester) async {
            debugDefaultTargetPlatformOverride = TargetPlatform.android;
            try {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              tester.view.padding = const FakeViewPadding(top: 28, bottom: 48);
              tester.view.viewPadding = const FakeViewPadding(
                top: 28,
                bottom: 48,
              );
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
                      api: ApiClient(backend: _MapBackend()),
                      dining: _ok([
                        DiningLocation(id: 1, name: 'Beanz', isOpen: true),
                      ]),
                      events: _ok<CampusEvent>(const []),
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
              expect(
                tester.takeException(),
                isNull,
                reason: 'the map card must lay out on a phone',
              );

              final headerHeight = tester
                  .getSize(find.byType(TodayHeader))
                  .height;
              final position = tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position;
              for (final offset
                  in scrolled ? [300.0, 700.0, 100000.0] : [0.0]) {
                position.jumpTo(offset.clamp(0, position.maxScrollExtent));
                await tester.pump(const Duration(milliseconds: 300));
                expect(tester.takeException(), isNull);

                final rects = [
                  for (final type in [CompactCard, CardShell])
                    for (final element in find.byType(type).evaluate())
                      tester.getRect(find.byWidget(element.widget)),
                ];
                for (final (i, a) in rects.indexed) {
                  expect(a.isFinite, isTrue, reason: '$a');
                  expect(a.height, lessThan(2500), reason: '$a');
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

                // the page ends where its last card does, with no blank stretch
                if (position.pixels >= position.maxScrollExtent - 1) {
                  final last = rects
                      .map((r) => r.bottom)
                      .reduce((a, b) => a > b ? a : b);
                  expect(
                    size.height - last,
                    lessThan(size.height / 2),
                    reason: 'blank page end, last card ends at $last',
                  );
                }
                if (position.pixels < headerHeight - 8) {
                  // under the large date nothing is painted above the grid's top
                  final gridTop = rects
                      .map((r) => r.top)
                      .reduce((a, b) => a < b ? a : b);
                  expect(
                    gridTop,
                    greaterThanOrEqualTo(headerHeight - position.pixels - 1),
                    reason: 'a card above the grid',
                  );
                }
              }
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }
    }
  }
}
