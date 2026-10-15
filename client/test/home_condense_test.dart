/// The phone dashboard's condensed layout (under 600pt), with real data.
///
/// Measures what the owner's targets name: page margin 16, card padding 16,
/// radius 24, rows 52 with a 4 gap and a 32 icon circle, an inline 28 hero
/// pill, a one line 28 "+N open" footer, card gap 10, cards as tall as their
/// content and a 48 masthead. Run with --dart-define=MEASURE=true to print the
/// numbers.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart' show CardHero;
import 'package:tigerhub/widgets/status_row.dart';
import 'package:tigerhub/widgets/touch_target.dart';

import 'golden_harness.dart';

const _measure = bool.fromEnvironment('MEASURE');

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) =>
    Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

const _names = [
  'Crossroads',
  'Gracies',
  'Global Village Cantina',
  'Brick City Cafe',
  'Beanz',
  "Ben & Jerry's",
  'Market at Global Village',
  'Corner Store',
  "Java Wally's",
  'Artesano Bakery',
  'Grind House',
  'Commons',
  'Olive Oil Cafe',
  'Tiger Bytes',
  "Sol's Underground",
  'Late Night Grill',
  'Pizza Pantry',
  'Taco Truck',
  'Smoothie Stop',
  'Campus Center Cafe',
  'Midnight Oil',
  'Dunkin',
  'Starbucks',
  'Panda Express',
];

/// 24 locations, the first 14 open, five with an occupancy reading.
final _dining = _ok([
  for (var i = 0; i < _names.length; i++)
    DiningLocation(
      id: i + 1,
      name: _names[i],
      isOpen: i < 14,
      category: 'dining',
      categoryName: 'Dining',
      closesAt: i < 14 ? DateTime.utc(2099, 1, 1, 23) : null,
      opensAt: i < 14 ? null : DateTime.utc(2099, 1, 2, 12),
      occupancy: i < 5
          ? Occupancy(count: 20 + i, maxOcc: 100, percentFull: 20 + i * 15)
          : null,
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

ThemeData _theme(Brightness brightness) => AppTheme.from(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFFF76902),
    brightness: brightness,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  void phoneView(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    double ratio = 3,
  }) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = size * ratio;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  HomeScreen home(ValueChanged<int>? onGoToTab) => HomeScreen(
    api: ApiClient(backend: _EmptyBackend()),
    dining: _dining,
    events: _events,
    chefs: _chefs,
    areas: _ok<HousingArea>(const []),
    onRefresh: () async {},
    onGoToTab: onGoToTab ?? (_) {},
  );

  Future<void> pumpHome(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    Brightness brightness = Brightness.dark,
    double? boxHeight,
    ValueChanged<int>? onGoToTab,
  }) async {
    phoneView(tester, size, scale: scale);
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(brightness),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('shot'),
            child: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(height: boxHeight, child: home(onGoToTab)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect card(WidgetTester tester, int index) =>
      tester.getRect(find.byType(CardShell).at(index));

  void report(String label, Map<String, Object> values) {
    if (_measure) debugPrint('MEASURE $label ${values.toString()}');
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    final name = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$name: the condensed card numbers', (tester) async {
      await pumpHome(tester, size);

      final dining = card(tester, 0);
      final events = card(tester, 1);
      final chefs = card(tester, 2);

      // page margin 16, so the card is the window less 32
      expect(dining.left, 16);
      expect(dining.width, size.width - 32);
      // gap between cards 10
      expect(events.top - dining.bottom, 10);
      expect(chefs.top - events.bottom, 10);

      // radius 24 and padding 16
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(CardShell).first,
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.borderRadius, BorderRadius.circular(24));

      // title row 28 (hero pill), content 12 below: first row at card top + 56
      final rows = find.descendant(
        of: find.byType(CardShell).first,
        matching: find.byType(StatusRow),
      );
      expect(rows, findsNWidgets(4));
      final firstRow = tester.getRect(
        find
            .descendant(of: rows.first, matching: find.byType(Material))
            .first,
      );
      expect(firstRow.top - dining.top, 56);
      // rows 52 tall, 4 apart
      final tops = [
        for (var i = 0; i < 4; i++)
          tester
              .getRect(
                find
                    .descendant(of: rows.at(i), matching: find.byType(Material))
                    .first,
              )
              .top,
      ];
      expect(firstRow.height, 52);
      expect(tops[1] - tops[0], 56);
      expect(tops[3] - tops[2], 56);

      // inline hero pill, 28 tall, right of the title; no scalloped blob
      final pill = tester.getRect(
        find.descendant(
          of: find.byType(CardShell).first,
          matching: find.byType(CardHero),
        ),
      );
      expect(pill.height, 28);
      expect(pill.right, dining.right - 16);
      expect(find.text('14 open'), findsOneWidget);

      // footer: one 28 text row, "+10 open", directly under the rows
      final footer = find.text('+10 open');
      expect(footer, findsOneWidget);
      expect(tester.getSize(footer).height, lessThanOrEqualTo(28));

      // 4 rows: about 330 tall. 344: the footer's 48 tall hit region (see the
      // footer test below) is real layout space, 12 more than a 36 block.
      expect(dining.height, 344);

      final chefRow = tester.getRect(
        find
            .descendant(
              of: find
                  .descendant(
                    of: find.byType(CardShell).at(2),
                    matching: find.byType(StatusRow),
                  )
                  .first,
              matching: find.byType(Material),
            )
            .first,
      );
      // Visiting Chefs with data: the target is 56, and it is NOT met. The
      // title, the "2 today" pill and the three 32 wide edit controls do not fit
      // on one row of a 358 (or 408) wide card, so the title wraps beside the
      // controls and the header, which keeps the same height in edit mode, is
      // 56 tall instead of 32 (16 + 56 + 8 = 80). Pinned here so a change shows.
      expect(chefRow.top - chefs.top, 80);

      report(name, {
        'chefsTopToFirstRow': chefRow.top - chefs.top,
        'diningHeight': dining.height,
        'eventsHeight': events.height,
        'chefsHeight': chefs.height,
        'gap': events.top - dining.bottom,
        'topToFirstRow': firstRow.top - dining.top,
        'rowHeight': firstRow.height,
        'pillHeight': pill.height,
      });
    });

    testWidgets('$name: icon circles are 32 with an 18 glyph', (tester) async {
      await pumpHome(tester, size);
      final circles = find.descendant(
        of: find.byType(DiningRow).first,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(tester.getSize(circles.first), const Size(32, 32));
      expect(tester.widget<Icon>(find.descendant(of: circles.first, matching: find.byType(Icon))).size, 18);
    });

    testWidgets('$name: fonts are 22 / 17 / 14 with no tracking', (tester) async {
      await pumpHome(tester, size);
      final title = tester.widget<Text>(find.text('Dining')).style!;
      expect(title.fontSize, 22);
      expect(title.letterSpacing, 0);
      // the first row's two lines: name, then status
      final lines = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(DiningRow).first,
              matching: find.byType(Text),
            ),
          )
          .toList();
      expect(lines[0].style!.fontSize, 17);
      expect(lines[0].style!.letterSpacing, 0);
      expect(lines[1].style!.fontSize, 14);
      expect(lines[1].style!.letterSpacing, 0);
    });

    testWidgets('$name: the "+10 open" footer is a 28 row with a 48 hit region', (
      tester,
    ) async {
      final taps = <int>[];
      await pumpHome(tester, size, onGoToTab: taps.add);

      final label = find.text('+10 open');
      final visual = tester.getRect(label);
      expect(visual.height, lessThanOrEqualTo(28));
      final target = tester.getRect(
        find.ancestor(of: label, matching: find.byType(TouchTarget)),
      );
      expect(target.height, greaterThanOrEqualTo(48));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.contains(visual.center), isTrue);

      // a tap above and below the visual row, in the region, goes through
      for (final dy in [-20.0, 20.0]) {
        await tester.tapAt(Offset(visual.center.dx, visual.center.dy + dy));
        await tester.pump();
      }
      expect(taps, [1, 1]);
    });

    testWidgets('$name: at 2x names and statuses take two lines, not an ellipsis', (
      tester,
    ) async {
      await pumpHome(tester, size, scale: 2);
      final rows = find.byType(DiningRow);
      for (var i = 0; i < 4; i++) {
        final texts = find.descendant(
          of: rows.at(i),
          matching: find.byType(Text),
        );
        for (final text in tester.widgetList<Text>(texts)) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byWidget(text),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '"${text.data}" was cut off at 2x',
          );
        }
      }
    });

    testWidgets('$name: at 1x normal names keep rows 52 tall', (tester) async {
      await pumpHome(tester, size);
      // every dashboard row: dining, events and chefs
      final rows = find.byType(StatusRow);
      expect(rows.evaluate().length, greaterThanOrEqualTo(8));
      for (var i = 0; i < rows.evaluate().length; i++) {
        final height = tester
            .getRect(
              find
                  .descendant(of: rows.at(i), matching: find.byType(Material))
                  .first,
            )
            .height;
        expect(height, 52, reason: 'row $i');
      }
    });

    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        final shot = '${name}_${brightness.name}_${scale.toInt()}x';
        goldenWidgets('golden home condense $shot', (tester) async {
          await pumpHome(
            tester,
            size,
            scale: scale,
            brightness: brightness,
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shot')),
          );
          final image = (await tester.runAsync<ui.Image>(
            () => boundary.toImage(pixelRatio: 3),
          ))!;
          await expectLater(
            image,
            matchesGoldenFile('goldens/home_condense_$shot.png'),
          );
        });
      }
    }
  }

  // The real shell on a phone: the masthead is 48 tall.
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    testWidgets('${size.width.toInt()}x${size.height.toInt()}: masthead is 48', (
      tester,
    ) async {
      phoneView(tester, size);
      final scheme = SchemeController();
      await scheme.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.dark),
          home: AppShell(
            api: ApiClient(backend: _EmptyBackend()),
            scheme: scheme,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mastheadHeight = tester.getTopLeft(find.byType(HomeScreen)).dy;
      report('masthead ${size.width.toInt()}', {'height': mastheadHeight});
      expect(mastheadHeight, 48);
      scheme.dispose();
    });
  }

  // Acceptance: at 440x956, two full cards and the start of a third show on
  // Today. The Today content area is the window less the top safe area (62 on
  // the 17 Pro Max), the 48 masthead and the tab bar (121 including its safe
  // area today).
  testWidgets('440x956: two full cards and the start of a third on Today', (
    tester,
  ) async {
    const content = 956 - 62 - 48 - 121.0;
    await pumpHome(tester, const Size(440, 956), boxHeight: content);
    final first = card(tester, 0);
    final second = card(tester, 1);
    final third = card(tester, 2);
    report('acceptance', {
      'content': content,
      'card1Bottom': first.bottom,
      'card2Bottom': second.bottom,
      'card3Top': third.top,
    });
    expect(first.bottom, lessThanOrEqualTo(content));
    expect(second.bottom, lessThanOrEqualTo(content));
    expect(third.top, lessThan(content - 30), reason: 'the third card is not visible');
    expect(third.bottom, greaterThan(content), reason: 'the third is only started');
  });
}
