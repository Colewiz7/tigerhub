/// Dashboard layouts at 600pt and wider are unchanged from the base commit.
///
/// The A+B condense is phone only (under 600pt). This pins the Today cards at
/// 600, 768 and 1024 wide, at 1x and 2x text, to numbers measured on base
/// commit edc9f6c with this same test (see `_measure` below): card size, title
/// size and place, hero size and place, where the content starts, and the first
/// row's height. Edit mode is not covered: the E header rewrite changes it on
/// purpose (whole word titles, same header height in both modes).
///
/// One difference is deliberate and not covered by the numbers: empty states
/// now center in their card at every width (step 4 of the A+B pass).
///
/// To re-measure on another commit, copy this file there and run
/// `flutter test --dart-define=MEASURE=true test/wide_layout_base_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

const _measure = bool.fromEnvironment('MEASURE');

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) =>
    Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

final _dining = _ok([
  for (var i = 0; i < 12; i++)
    DiningLocation(
      id: i + 1,
      name: 'Place number $i',
      isOpen: i < 7,
      category: 'dining',
      categoryName: 'Dining',
      closesAt: i < 7 ? DateTime.utc(2099, 1, 1, 23) : null,
      opensAt: i < 7 ? null : DateTime.utc(2099, 1, 2, 12),
    ),
]);

final _chefs = _ok([
  const MenuItem(id: 1, locationName: 'Gracies', name: 'Chef Marco'),
  const MenuItem(id: 2, locationName: 'Crossroads', name: 'Chef Ayana'),
]);

final _events = _ok([
  for (final (i, organizer) in ['Robotics Club', 'SWE', 'Art Club'].indexed)
    CampusEvent(
      uid: 'e$i',
      source: 'test',
      title: 'Meeting $i',
      startsAt: DateTime.utc(2099, 1, 1 + i, 15),
      organizer: organizer,
      organizerKey: organizer.toLowerCase(),
    ),
]);

String _r(Rect rect) =>
    '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},'
    '${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)}';

/// Numbers measured on base commit edc9f6c, one line per (width, text scale,
/// card), in the form `card | title | hero | content top | first row`, every
/// rect relative to the card's top left as left,top,widthxheight.
const _baseline = <String, List<String>>{
  '600 @ 1.0x': [
    '572.0x558.0 | 57.0,53.0,85.6x34.0 | 458.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,520.0x72.0',
    '572.0x446.0 | 57.0,53.0,92.1x34.0 | 458.0,26.0,88.0x88.0 | 126.0 | 26.0,175.0,520.0x72.0',
    '572.0x296.0 | 57.0,53.0,186.3x34.0 | 458.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,520.0x72.0',
    '572.0x234.0 | 57.0,26.0,209.8x34.0 | none | 72.0 | none',
  ],
  '600 @ 2.0x': [
    '572.0x486.0 | 57.0,35.5,170.6x69.0 | 458.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,520.0x144.0',
    '572.0x394.0 | 57.0,35.5,183.5x69.0 | 458.0,26.0,88.0x88.0 | 126.0 | 26.0,202.0,520.0x119.0',
    '572.0x440.0 | 57.0,35.5,371.2x69.0 | 458.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,520.0x144.0',
    '572.0x293.0 | 57.0,26.0,418.1x69.0 | none | 107.0 | none',
  ],
  '768 @ 1.0x': [
    '740.0x558.0 | 57.0,53.0,85.6x34.0 | 626.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,688.0x72.0',
    '740.0x446.0 | 57.0,53.0,92.1x34.0 | 626.0,26.0,88.0x88.0 | 126.0 | 26.0,175.0,688.0x72.0',
    '740.0x296.0 | 57.0,53.0,186.3x34.0 | 626.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,688.0x72.0',
    '740.0x234.0 | 57.0,26.0,209.8x34.0 | none | 72.0 | none',
  ],
  '768 @ 2.0x': [
    '740.0x486.0 | 57.0,35.5,170.6x69.0 | 626.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,688.0x144.0',
    '740.0x394.0 | 57.0,35.5,183.5x69.0 | 626.0,26.0,88.0x88.0 | 126.0 | 26.0,202.0,688.0x119.0',
    '740.0x440.0 | 57.0,35.5,371.2x69.0 | 626.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,688.0x144.0',
    '740.0x293.0 | 57.0,26.0,418.1x69.0 | none | 107.0 | none',
  ],
  '1024 @ 1.0x': [
    '492.0x558.0 | 57.0,53.0,85.6x34.0 | 378.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,440.0x72.0',
    '492.0x446.0 | 57.0,53.0,92.1x34.0 | 378.0,26.0,88.0x88.0 | 126.0 | 26.0,175.0,440.0x72.0',
    '492.0x296.0 | 57.0,53.0,186.3x34.0 | 378.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,440.0x72.0',
    '492.0x234.0 | 57.0,26.0,209.8x34.0 | none | 72.0 | none',
  ],
  '1024 @ 2.0x': [
    '492.0x486.0 | 57.0,35.5,170.6x69.0 | 378.0,26.0,88.0x88.0 | 126.0 | 26.0,126.0,440.0x144.0',
    '492.0x394.0 | 57.0,35.5,183.5x69.0 | 378.0,26.0,88.0x88.0 | 126.0 | 26.0,202.0,440.0x119.0',
    '492.0x490.0 | 57.0,26.0,311.0x138.0 | 378.0,51.0,88.0x88.0 | 176.0 | 26.0,176.0,440.0x144.0',
    '492.0x410.0 | 57.0,26.0,409.0x138.0 | none | 176.0 | none',
  ],
  // every card empty (Visiting Chefs, the third, fills its cell)
  '600 @ 1.0x empty': [
    '572.0x234.0 | 57.0,26.0,85.6x34.0 | none | 72.0 | none',
    '572.0x234.0 | 57.0,26.0,92.1x34.0 | none | 72.0 | none',
    '572.0x560.0 | 57.0,26.0,186.3x34.0 | none | 72.0 | none',
    '572.0x234.0 | 57.0,26.0,209.8x34.0 | none | 72.0 | none',
  ],
  '600 @ 2.0x empty': [
    '572.0x293.0 | 57.0,26.0,170.6x69.0 | none | 107.0 | none',
    '572.0x293.0 | 57.0,26.0,183.5x69.0 | none | 107.0 | none',
    '572.0x560.0 | 57.0,26.0,371.2x69.0 | none | 107.0 | none',
    '572.0x293.0 | 57.0,26.0,418.1x69.0 | none | 107.0 | none',
  ],
  '768 @ 1.0x empty': [
    '740.0x234.0 | 57.0,26.0,85.6x34.0 | none | 72.0 | none',
    '740.0x234.0 | 57.0,26.0,92.1x34.0 | none | 72.0 | none',
    '740.0x560.0 | 57.0,26.0,186.3x34.0 | none | 72.0 | none',
    '740.0x234.0 | 57.0,26.0,209.8x34.0 | none | 72.0 | none',
  ],
  '768 @ 2.0x empty': [
    '740.0x293.0 | 57.0,26.0,170.6x69.0 | none | 107.0 | none',
    '740.0x293.0 | 57.0,26.0,183.5x69.0 | none | 107.0 | none',
    '740.0x560.0 | 57.0,26.0,371.2x69.0 | none | 107.0 | none',
    '740.0x293.0 | 57.0,26.0,418.1x69.0 | none | 107.0 | none',
  ],
  '1024 @ 1.0x empty': [
    '492.0x234.0 | 57.0,26.0,85.6x34.0 | none | 72.0 | none',
    '492.0x234.0 | 57.0,26.0,92.1x34.0 | none | 72.0 | none',
    '492.0x560.0 | 57.0,26.0,186.3x34.0 | none | 72.0 | none',
    '492.0x234.0 | 57.0,26.0,209.8x34.0 | none | 72.0 | none',
  ],
  '1024 @ 2.0x empty': [
    '492.0x293.0 | 57.0,26.0,170.6x69.0 | none | 107.0 | none',
    '492.0x293.0 | 57.0,26.0,183.5x69.0 | none | 107.0 | none',
    '492.0x560.0 | 57.0,26.0,371.2x69.0 | none | 107.0 | none',
    '492.0x410.0 | 57.0,26.0,409.0x138.0 | none | 176.0 | none',
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real Rubik, loaded once for the file the way goldenWidgets does.
  setUpAll(loadGoldenFonts);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final empty in const [false, true]) {
  for (final width in const [600.0, 768.0, 1024.0]) {
    for (final scale in const [1.0, 2.0]) {
      final key = '${width.toInt()} @ ${scale}x${empty ? ' empty' : ''}';
      testWidgets('wide dashboard at $key matches the base commit', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1100);
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final lines = <String>[];
        // 2x text overflows inside some cells on both commits; geometry, not
        // overflow, is what is compared here. The reports are dropped rather
        // than captured: the harness's capture formats the whole widget tree
        // for each one, which does not finish at 2x.
        final previous = FlutterError.onError;
        FlutterError.onError = (_) {};
        addTearDown(() => FlutterError.onError = previous);
        await (() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.from(
                ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
              ),
              home: Scaffold(
                body: HomeScreen(
                  api: ApiClient(backend: _EmptyBackend()),
                  dining: empty ? _ok<DiningLocation>(const []) : _dining,
                  events: empty ? _ok<CampusEvent>(const []) : _events,
                  chefs: empty ? _ok<MenuItem>(const []) : _chefs,
                  areas: _ok<HousingArea>(const []),
                  onRefresh: () async {},
                  onGoToTab: (_) {},
                ),
              ),
            ),
          );
          // Fixed pumps, not pumpAndSettle: at 2x text the base commit never
          // settles at 600 wide.
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }

          final shells = find.byType(CardShell);
          for (var i = 0; i < shells.evaluate().length; i++) {
            final shell = shells.at(i);
            final card = tester.getRect(shell);
            Rect rel(Rect r) => r.shift(-card.topLeft);
            Finder within(Finder f) => find.descendant(of: shell, matching: f);

            final title = rel(tester.getRect(within(find.byType(Text)).first));
            final hero = within(find.byType(ScallopedBadge));
            final content = rel(
              tester.getRect(
                within(
                  find.byWidgetPredicate(
                    (w) =>
                        w is AnimatedSwitcher &&
                        w.duration == const Duration(milliseconds: 140),
                  ),
                ).first,
              ),
            );
            final rows = within(find.byType(StatusRow));
            final firstRow = rows.evaluate().isEmpty
                ? 'none'
                : _r(rel(tester.getRect(rows.first)));
            lines.add(
              '${card.width.toStringAsFixed(1)}x${card.height.toStringAsFixed(1)}'
              ' | ${_r(title)}'
              ' | ${hero.evaluate().isEmpty ? 'none' : _r(rel(tester.getRect(hero.first)))}'
              ' | ${content.top.toStringAsFixed(1)}'
              ' | $firstRow',
            );
          }
        })();
        FlutterError.onError = previous;

        if (_measure) {
          debugPrint("BASE '$key': [");
          for (final line in lines) {
            debugPrint("  '$line',");
          }
          debugPrint('],');
        } else {
          expect(lines, _baseline[key]);
        }
      });
    }
  }
  }
}
