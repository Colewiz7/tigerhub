/// Today on an Android phone, where the saved layout replaces the default four
/// cards after the first frame. No card may be painted anywhere but where it
/// settles, on any frame: a card that starts from the old layout's offsets
/// slides over the header and the cards around it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/compact_card.dart';

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

const _saved = [
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
  CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs),
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(id: 'housing-0', type: ModuleType.mailingAddress),
];

List<Rect> _cards(WidgetTester tester) => [
  for (final type in [CompactCard, CardShell])
    for (final i in List.generate(
      find.byType(type).evaluate().length,
      (i) => i,
    ))
      tester.getRect(find.byType(type).at(i)),
];

void main() {
  // real Rubik, Ahem would make every glyph a full em
  setUpAll(loadGoldenFonts);
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  Future<void> pumpToday(WidgetTester tester, Size size, double scale) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = scale == 2 ? 2 : 1;
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 48);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: HomeScreen(
            api: ApiClient(backend: _EmptyBackend()),
            dining: _ok<DiningLocation>(const []),
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
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final scale in const [1.0, 2.0]) {
      for (final scrolled in const [false, true]) {
        final name =
            '${size.width.toInt()}x${size.height.toInt()} ${scale.toInt()}x text ${scrolled ? 'scrolled' : 'unscrolled'}';

        testWidgets(
          '$name: the saved layout never paints a card off its place',
          (tester) async {
            try {
              final frames = <List<Rect>>[];
              // first launch: the default four cards are drawn, then the saved
              // layout loads
              await DashboardStore.save(_saved);
              await pumpToday(tester, size, scale);
              if (scrolled) {
                // and the page is scrolled before the cards have settled
                await tester.pump(const Duration(milliseconds: 16));
                final position = tester
                    .state<ScrollableState>(find.byType(Scrollable).first)
                    .position;
                position.jumpTo(position.maxScrollExtent.clamp(0, 300));
              }
              for (var i = 0; i < 40; i++) {
                await tester.pump(const Duration(milliseconds: 16));
                frames.add(_cards(tester));
              }
              await tester.pumpAndSettle();
              final settled = _cards(tester);

              // the same cards on every frame once they exist, none away from home
              for (final (i, frame) in frames.indexed) {
                if (frame.length != settled.length) continue;
                for (final (j, rect) in frame.indexed) {
                  expect(
                    rect.top,
                    closeTo(settled[j].top, 0.5),
                    reason: 'frame $i card $j',
                  );
                  expect(
                    rect.left,
                    closeTo(settled[j].left, 0.5),
                    reason: 'frame $i card $j',
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
