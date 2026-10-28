/// Dashboard layouts at 600pt and wider are unchanged from the base commit.
///
/// The A+B condense is phone only (under 600pt). This pins the Today cards at
/// 600, 768 and 1024 wide, at 1x and 2x text, in normal and edit mode, with
/// data and with every card empty, to numbers measured on base commit edc9f6c
/// with this same test (see [_measure]): card size, title and hero size and
/// place, where the content starts, the first row, the edit controls, and the
/// empty state block. Only the cases listed under [_housingOldHeight] and
/// [_shorterCopySizes] are exempt, because shorter copy changed their size.
///
/// The one deliberate difference is the empty state block's horizontal place:
/// the owner's list says empty states are centered in their card, and the base
/// left aligned them at every width (the Dining, Events and Mailing Address
/// cards). So that field is pinned twice: against the base's size and top (they
/// must not move), and against the centered left edge it has now.
///
/// To re-measure on another commit, copy this file there and run
/// `flutter test --dart-define=MEASURE=true test/wide_layout_base_test.dart`.
library;

import 'dart:io';

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
import 'package:tigerhub/widgets/empty_state.dart';
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

Result<Collection<T>> _ok<T>(List<T> data) => Result(
  value: Collection<T>(data: data, stale: false),
  state: DataState.ok,
);

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
      location: i == 1 ? 'SAU 2nd floor' : null,
      organizer: organizer,
      organizerKey: organizer.toLowerCase(),
    ),
  // all day, and one that is over: the other trailing texts a row can have
  CampusEvent(
    uid: 'allday',
    source: 'test',
    title: 'Career fair',
    startsAt: DateTime.utc(2099, 1, 5, 5),
    allDay: true,
    location: 'Gordon Field House',
    organizer: 'Robotics Club',
    organizerKey: 'robotics club',
  ),
  CampusEvent(
    uid: 'past',
    source: 'test',
    title: 'Old meeting',
    startsAt: DateTime.utc(2000, 1, 1, 15),
    endsAt: DateTime.utc(2000, 1, 1, 16),
    organizer: 'SWE',
    organizerKey: 'swe',
  ),
]);

/// The same events with the all day one and the past one first, which is the
/// order a group shows its single row from.
final _eventsLeadingWithOddRows = _ok([
  ..._events.value!.data.where((e) => e.uid == 'allday' || e.uid == 'past'),
  ..._events.value!.data.where((e) => e.uid != 'allday' && e.uid != 'past'),
]);

String _r(Rect rect) =>
    '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},'
    '${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)}';

/// The base commit's numbers, captured by running this file's measurement
/// (`--dart-define=MEASURE=true`) on edc9f6c in a separate worktree and saving
/// what it printed in test/fixtures/wide_layout_base.txt.
///
/// Per (width, text scale, variant, mode) and card, `BASE` lines are
/// `card | title | hero | content top | first row | edit controls`, every rect
/// relative to the card's top left as left,top,widthxheight, and `EMPTY` lines
/// are the empty state block ('none' when the card has none) as the base had
/// it. Only that block's left edge differs now: it is centered.
({
  Map<String, List<String>> base,
  Map<String, List<String>> empty,
  Map<String, List<String>> text,
})
_loadBase() {
  final base = <String, List<String>>{};
  final empty = <String, List<String>>{};
  final text = <String, List<String>>{};
  Map<String, List<String>>? into;
  String? key;
  for (final line in File(
    'test/fixtures/wide_layout_base.txt',
  ).readAsLinesSync()) {
    final header = RegExp(r"^(BASE|EMPTY|TEXT) '(.*)': \[$").firstMatch(line);
    if (header != null) {
      into = switch (header.group(1)) {
        'BASE' => base,
        'EMPTY' => empty,
        _ => text,
      };
      key = header.group(2);
      into[key!] = [];
    } else if (line.startsWith("  '")) {
      into![key]!.add(line.substring(3, line.length - 2));
    }
  }
  return (base: base, empty: empty, text: text);
}

// --- the only places shorter copy changed geometry ---
// every other number must match the base commit exactly

// housing is the fourth card on the dashboard
const _housing = 3;

// 1024 @ 2x: "Housing areas are unavailable" wrapped to two lines in the
// 492 wide card, "Housing unavailable" fits on one, so the card loses a line
// of 2x text (48pt): 410 -> 362. Every variant of 1024 @ 2x has it.
const _housingOldHeight = '492.0x410.0';
const _housingNewHeight = '492.0x362.0';

// empty state block sizes (widthxheight) by the copy that changed them:
//   Housing, 1x: 243.1x96.0 -> 163.9x96.0, 2x: 479.0x120.0 -> 323.0x120.0
//     "Housing areas are unavailable" -> "Housing unavailable"
//   Housing, 1024 @ 2x: 424.0x168.0 -> 323.0x120.0, same string change, the
//     old copy wrapped to two lines and the new copy is one
//   Dining, 1x: 166.7x96.0 -> 149.0x96.0, 2x: 328.1x120.0 -> 293.4x120.0
//     "Dining is unavailable" -> "Dining unavailable"
//   Events, 1x: 203.9x96.0 -> 131.7x96.0, 2x: 402.0x120.0 -> 259.6x120.0
//     "Nothing scheduled today" -> "No events today"
// Each exception names the cases it applies to (a substring of the case key),
// the card, and the old size, so another card can't ride on someone else's.
const _diningCard = 0;
const _eventsCard = 1;
const _shorterCopySizes = <({String cases, int card, String old, String now})>[
  (cases: '@ 1.0x', card: _housing, old: '243.1x96.0', now: '163.9x96.0'),
  (cases: '600 @ 2.0x', card: _housing, old: '479.0x120.0', now: '323.0x120.0'),
  (cases: '768 @ 2.0x', card: _housing, old: '479.0x120.0', now: '323.0x120.0'),
  (
    cases: '1024 @ 2.0x',
    card: _housing,
    old: '424.0x168.0',
    now: '323.0x120.0',
  ),
  (
    cases: '@ 1.0x empty',
    card: _diningCard,
    old: '166.7x96.0',
    now: '149.0x96.0',
  ),
  (
    cases: '@ 2.0x empty',
    card: _diningCard,
    old: '328.1x120.0',
    now: '293.4x120.0',
  ),
  (
    cases: '@ 1.0x empty',
    card: _eventsCard,
    old: '203.9x96.0',
    now: '131.7x96.0',
  ),
  (
    cases: '@ 2.0x empty',
    card: _eventsCard,
    old: '402.0x120.0',
    now: '259.6x120.0',
  ),
];

// status words went sentence case after the base, geometry stayed put
String _sentenceCaseStatus(String text) => text.replaceAllMapped(
  RegExp(r'\b(OPEN|ENDED|ALL DAY)\b'),
  (m) => switch (m[0]) {
    'OPEN' => 'Open',
    'ENDED' => 'Ended',
    _ => 'All day',
  },
);

// today hides ended events after the base: SWE loses Old meeting, so its
// count drops and its next event leads the group. geometry stayed put
String _endedDropsOff(String text) => text
    .replaceAll('SWE ¦ 2 ¦ Old meeting ¦ Sat 1 Jan, 10:00 AM ¦ Sat 1 Jan, 10:00 AM ¦ Ended', 'SWE ¦ 1 ¦ Meeting 1 ¦ SAU 2nd floor ¦ Fri 2 Jan, 10:00 AM')
    .replaceAll('SWE ¦ 2', 'SWE ¦ 1');

String _expectedEmptySize(String key, int card, String old) {
  for (final e in _shorterCopySizes) {
    if (e.card == card && e.old == old && key.contains(e.cases)) return e.now;
  }
  return old;
}

/// Every string a card shows, in tree order, joined with ' ¦ '. The rows'
/// own text (names, status lines, times, ENDED) is in here.
String _texts(WidgetTester tester, Finder within) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: within, matching: find.byType(Text)),
  ))
    t.data ?? t.textSpan?.toPlainText() ?? '',
].join(' ¦ ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real Rubik, loaded once for the file the way goldenWidgets does.
  setUpAll(loadGoldenFonts);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final edit in const [false, true]) {
    // 'rows' leads each Events group with the all day and the past event, so
    // their row text is on screen and compared too. The card shows one row per
    // group, and in the default data those two sit behind another event.
    for (final variant in const ['data', 'empty', 'rows']) {
      final empty = variant == 'empty';
      final rows = variant == 'rows';
      for (final width in const [600.0, 768.0, 1024.0]) {
        for (final scale in const [1.0, 2.0]) {
          final key =
              '${width.toInt()} @ ${scale}x${empty ? ' empty' : ''}'
              '${rows ? ' rows' : ''}${edit ? ' edit' : ''}';
          testWidgets('wide dashboard at $key matches the base commit', (
            tester,
          ) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 1100);
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearAllTestValues);

            final lines = <String>[];
            final blocks = <String>[];
            final texts = <String>[];
            // 2x text overflows inside some cells on both commits; geometry,
            // not overflow, is what is compared here. The reports are dropped
            // rather than captured: the harness's capture formats the whole
            // widget tree for each one, which does not finish at 2x.
            final previous = FlutterError.onError;
            FlutterError.onError = (_) {};
            addTearDown(() => FlutterError.onError = previous);

            Future<void> settle() async {
              // Fixed pumps, not pumpAndSettle.
              for (var i = 0; i < 4; i++) {
                await tester.pump(const Duration(milliseconds: 500));
              }
            }

            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.from(
                  ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
                ),
                home: Scaffold(
                  body: HomeScreen(
                    api: ApiClient(backend: _EmptyBackend()),
                    dining: empty ? _ok<DiningLocation>(const []) : _dining,
                    events: empty
                        ? _ok<CampusEvent>(const [])
                        : rows
                        ? _eventsLeadingWithOddRows
                        : _events,
                    chefs: empty ? _ok<MenuItem>(const []) : _chefs,
                    areas: _ok<HousingArea>(const []),
                    onRefresh: () async {},
                    onGoToTab: (_) {},
                  ),
                ),
              ),
            );
            await settle();

            if (edit) {
              final position = tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position;
              position.jumpTo(position.maxScrollExtent);
              await settle();
              await tester.tap(find.text('Customize'));
              await settle();
              position.jumpTo(0);
              await settle();
            }

            final shells = find.byType(CardShell);
            for (var i = 0; i < shells.evaluate().length; i++) {
              final shell = shells.at(i);
              final card = tester.getRect(shell);
              Rect rel(Rect r) => r.shift(-card.topLeft);
              Finder within(Finder f) =>
                  find.descendant(of: shell, matching: f);

              final title = rel(
                tester.getRect(within(find.byType(Text)).first),
              );
              final hero = within(find.byType(ScallopedBadge));
              final content = rel(
                tester.getRect(
                  within(
                    find.byWidgetPredicate(
                      (w) => w is KeyedSubtree && w.key is ValueKey<bool>,
                    ),
                  ).first,
                ),
              );
              final rows = within(find.byType(StatusRow));
              final firstRow = rows.evaluate().isEmpty
                  ? 'none'
                  : _r(rel(tester.getRect(rows.first)));

              String controls = 'none';
              if (edit) {
                final handle = Rect.fromCenter(
                  center: tester.getCenter(
                    within(find.byIcon(Icons.drag_indicator_rounded)),
                  ),
                  width: 32,
                  height: 32,
                );
                final inspect = tester.getRect(
                  within(find.byTooltip('Customize card')),
                );
                final remove = tester.getRect(
                  within(find.byTooltip('Remove card from Today')),
                );
                controls =
                    '${_r(rel(handle))} ${_r(rel(inspect))} ${_r(rel(remove))}';
              }

              lines.add(
                '${card.width.toStringAsFixed(1)}x${card.height.toStringAsFixed(1)}'
                ' | ${_r(title)}'
                ' | ${hero.evaluate().isEmpty ? 'none' : _r(rel(tester.getRect(hero.first)))}'
                ' | ${content.top.toStringAsFixed(1)}'
                ' | $firstRow'
                ' | $controls',
              );

              texts.add(_texts(tester, shell));

              final emptyState = within(find.byType(EmptyState));
              blocks.add(
                emptyState.evaluate().isEmpty
                    ? 'none'
                    : _r(
                        rel(
                          tester.getRect(
                            find
                                .descendant(
                                  of: emptyState,
                                  matching: find.byType(Column),
                                )
                                .first,
                          ),
                        ),
                      ),
              );
            }
            FlutterError.onError = previous;

            if (_measure) {
              debugPrint("BASE '$key': [");
              for (final line in lines) {
                debugPrint("  '$line',");
              }
              debugPrint('],');
              debugPrint("EMPTY '$key': [");
              for (final block in blocks) {
                debugPrint("  '$block',");
              }
              debugPrint('],');
              debugPrint("TEXT '$key': [");
              for (final text in texts) {
                debugPrint("  '$text',");
              }
              debugPrint('],');
            } else {
              final fixture = _loadBase();
              final expected = [...fixture.base[key]!];
              if (key.startsWith('1024 @ 2.0x')) {
                expected[_housing] = expected[_housing].replaceFirst(
                  _housingOldHeight,
                  _housingNewHeight,
                );
              }
              expect(lines, expected, reason: 'geometry moved');
              expect(
                texts,
                [for (final t in fixture.text[key]!) _endedDropsOff(_sentenceCaseStatus(t)).replaceAll('+1 organizers', '+1 organizer')],
                reason: 'row text changed',
              );

              // The empty state block: same size and top as the base, and
              // centered across its card (the base left aligned it).
              final base = fixture.empty[key]!;
              expect(blocks.length, base.length);
              for (var i = 0; i < blocks.length; i++) {
                if (base[i] == 'none') {
                  expect(blocks[i], 'none', reason: 'card $i');
                  continue;
                }
                List<double> parse(String s) => [
                  for (final n in s.split(RegExp(r'[,x]'))) double.parse(n),
                ];
                final now = parse(blocks[i]);
                final then = parse(base[i]);
                final sizeNow = '${now[2]}x${now[3]}';
                final sizeThen = '${then[2]}x${then[3]}';
                expect(now[1], then[1], reason: 'card $i empty block top');
                expect(
                  sizeNow,
                  _expectedEmptySize(key, i, sizeThen),
                  reason: 'card $i empty block size',
                );
                final cardWidth = double.parse(lines[i].split('x').first);
                expect(
                  now[0],
                  closeTo((cardWidth - now[2]) / 2, 1),
                  reason: 'card $i empty block is not centered across the card',
                );
              }
            }
          });
        }
      }
    }
  }
}
