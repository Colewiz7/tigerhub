/// The visiting chefs card in each of its states.
///
/// Available, a real quiet day, quiet with a next chef, and unavailable look
/// different on purpose: "Menus unavailable" must never read like "No visiting
/// chefs today". Goldens cover the two phone widths in both modes at text
/// scale 1.0 and 2.0 with real chef data, since an empty card cannot overflow
/// and proves nothing.
///
/// Regenerate with `flutter test --update-goldens test/visiting_chefs_card_test.dart`
/// and look at every image before committing.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/chef_family.dart';
import 'package:tigerhub/data/chef_location_color.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/upstream.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/more_row.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

class _FixedBackend implements Backend {
  const _FixedBackend(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async => body;

  @override
  void close() {}
}

final DateTime _checked =DateTime.now().subtract(const Duration(minutes: 5));

final _chefs = [
  MenuItem(
    id: 1,
    name: 'KO-BQ',
    locationName: 'The Cafe & Market at Crossroads',
    category: 'Visiting Chef',
    startsAt: DateTime.parse('2026-10-14T11:00:00-04:00'),
    endsAt: DateTime.parse('2026-10-14T14:00:00-04:00'),
    cuisine: 'Korean fusion cuisine',
  ),
  MenuItem(
    id: 2,
    name: 'Tandoor of India',
    locationName: 'RITZ',
    category: 'Visiting Chef',
    startsAt: DateTime.parse('2026-10-14T16:00:00-04:00'),
    endsAt: DateTime.parse('2026-10-14T19:00:00-04:00'),
  ),
  const MenuItem(
    id: 3,
    name: 'P.H. Express',
    locationName: 'Kitchen at Brick City',
    category: 'Visiting Chef',
  ),
];

final _states = <String, Result<Collection<MenuItem>>>{
  'available': Result(
    value: ChefCollection(data: _chefs, stale: false),
    state: DataState.ok,
  ),
  'empty': const Result(
    value: ChefCollection(
      data: [],
      stale: false,
      availability: Availability.empty,
    ),
    state: DataState.ok,
  ),
  'next': Result(
    value: ChefCollection(
      data: const [],
      stale: false,
      availability: Availability.empty,
      next: UpcomingChef(
        date: DateTime.utc(2026, 10, 16),
        name: 'Tandoor of India',
        locationName: 'The Cafe & Market at Crossroads',
      ),
    ),
    state: DataState.ok,
  ),
  'unavailable': Result(
    value: ChefCollection(
      data: const [],
      stale: false,
      lastUpdated: _checked,
      availability: Availability.unavailable,
    ),
    state: DataState.ok,
  ),
};

Future<void> _pump(
  WidgetTester tester, {
  required Result<Collection<MenuItem>> result,
  required Size size,
  required Brightness brightness,
  required double scale,
  // A phone card is as tall as its content (main's condensed dashboard), so
  // there is no box. Only a 600pt+ cell bounds the card, and passes a height.
  double? height,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFF76902),
    brightness: brightness,
  );
  // AppTheme replaces the whole text theme, which drops ThemeData's family,
  // so the family is named here or the images would be drawn in Ahem.
  final theme = AppTheme.from(scheme);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: AppTheme.fontFamily),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: scheme.surface,
        // The dashboard lists its cards in a scroll view, so a phone card has
        // no height to fill and is as tall as its content.
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            child: RepaintBoundary(
              key: const ValueKey('card'),
              child: height == null
                  ? VisitingChefsCard(result: result)
                  : SizedBox(
                      height: height,
                      child: VisitingChefsCard(result: result),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Whether [finder]'s text was cut by a line limit.
bool _cut(WidgetTester tester, Finder finder) {
  final paragraph = find.descendant(of: finder, matching: find.byType(RichText));
  return tester.renderObject<RenderParagraph>(paragraph.first).didExceedMaxLines;
}

void main() {
  // Fonts for the goldens come from goldenWidgets (golden_harness.dart).
  setUp(() => RitClock.pin(DateTime.utc(2026, 10, 14, 16)));
  tearDown(RitClock.reset);

  group('card rhythm', () {
    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        // 16 card padding on the sides and top; the rows hold 4 of their own.
        // Before, a one line title sat in a header band reserved for the old
        // row of edit controls, leaving 36 (390, 1x) and 46 (440, 2x) between
        // the title and the first row, and the last row sat 16 above the
        // card's edge on top of its own 4.
        goldenWidgets('the header and the rows sit close at $width, ${scale}x', (
          tester,
        ) async {
          await _pump(
            tester,
            result: _states['available']!,
            size: Size(width, 844),
            brightness: Brightness.light,
            scale: scale,
          );
          final card = tester.getRect(find.byKey(const ValueKey('card')));
          final title = tester.getRect(find.text('Visiting chefs'));
          final pill = tester.getRect(find.text('3 today'));
          final rows = find.byType(StatusRow);
          final first = tester.getRect(rows.first);
          final last = tester.getRect(rows.last);

          final headerBottom = title.bottom > pill.bottom ? title.bottom : pill.bottom;
          // At 440 and 2x the title wraps beside the pill and edit mode would
          // grow the card by 86 without the 38 it keeps; 48 is the most the
          // reorder tests allow, so that one stays.
          final most = width == 440 && scale == 2 ? 46 : 12;
          expect(first.top - headerBottom, lessThanOrEqualTo(most),
              reason: 'header to the first row');
          expect(card.bottom - last.bottom, 12, reason: 'last row to the card edge');
          for (final row in [first, last]) {
            expect(row.height, greaterThanOrEqualTo(48), reason: 'tap target');
          }
        });
      }
    }
  });

  group('time and location rows', () {
    // The longest real location, with a time that is not on the hour.
    final long = [
      MenuItem(
        id: 1,
        name: 'Tandoor of India',
        locationName: 'The Cafe & Market at Crossroads',
        startsAt: DateTime.parse('2026-10-14T11:00:00-04:00'),
        endsAt: DateTime.parse('2026-10-14T14:30:00-04:00'),
      ),
      MenuItem(
        id: 2,
        name: 'KO-BQ',
        locationName: 'Kitchen at Brick City',
        startsAt: DateTime.parse('2026-10-14T16:00:00-04:00'),
        endsAt: DateTime.parse('2026-10-14T19:30:00-04:00'),
      ),
    ];
    final result = Result<Collection<MenuItem>>(
      value: ChefCollection(data: long, stale: false),
      state: DataState.ok,
    );

    for (final brightness in Brightness.values) {
      testWidgets('a location is the same colour on the card and in the sheet, ${brightness.name}', (
        tester,
      ) async {
        await _pump(
          tester,
          result: result,
          size: const Size(390, 844),
          brightness: brightness,
          scale: 1,
        );
        Color? colourOf(Finder f) => tester.widget<Text>(f).style?.color;
        final want = {
          'The Cafe & Market at Crossroads': chefLocationColors[23]!,
          'Kitchen at Brick City': chefLocationColors[22]!,
        };
        for (final e in want.entries) {
          final c = brightness == Brightness.dark ? e.value.dark : e.value.light;
          expect(colourOf(find.text(e.key)), c, reason: 'card ${e.key}');
        }

        await tester.tap(find.text('Visiting chefs'));
        await tester.pumpAndSettle();
        for (final e in want.entries) {
          final c = brightness == Brightness.dark ? e.value.dark : e.value.light;
          final inSheet = find.descendant(of: find.byType(BottomSheet), matching: find.text(e.key));
          expect(colourOf(inSheet), c, reason: 'sheet ${e.key}');
        }
      });
    }

    testWidgets('from 600pt the time and the location share one line, still coloured', (
      tester,
    ) async {
      await _pump(
        tester,
        result: result,
        size: const Size(700, 900),
        brightness: Brightness.light,
        scale: 1,
        height: 560,
      );
      final time = find.text('11 AM to 2:30 PM');
      final place = find.text('Kitchen at Brick City');
      expect(time, findsOneWidget);
      expect(place, findsOneWidget);
      expect(tester.getTopLeft(place).dy, closeTo(tester.getTopLeft(find.text('4 PM to 7:30 PM')).dy, 1));
      expect(tester.widget<Text>(place).style?.color, chefLocationColors[22]!.light);
    });

    testWidgets('the cuisine text is gone from the card and the sheet, the icon stays', (
      tester,
    ) async {
      await _pump(
        tester,
        result: _states['available']!,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.textContaining('Korean'), findsNothing);
      expect(find.byType(AppIcon), findsWidgets);
      final icons = find.byWidgetPredicate(
        (w) => w is AppIcon && w.kind == ChefFamily.asianNoodles.icon,
      );
      expect(icons, findsOneWidget, reason: 'KO-BQ, Korean fusion cuisine');

      await tester.tap(find.text('Visiting chefs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Korean'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byWidgetPredicate(
            (w) => w is AppIcon && w.kind == ChefFamily.asianNoodles.icon,
          ),
        ),
        findsOneWidget,
      );
    });

    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('the card shows each time and location whole at $width, ${scale}x', (
          tester,
        ) async {
          await _pump(
            tester,
            result: result,
            size: Size(width, 844),
            brightness: Brightness.light,
            scale: scale,
          );
          for (final text in [
            '11 AM to 2:30 PM',
            'The Cafe & Market at Crossroads',
            '4 PM to 7:30 PM',
            'Kitchen at Brick City',
          ]) {
            expect(find.text(text), findsOneWidget, reason: text);
            expect(_cut(tester, find.text(text)), isFalse, reason: text);
          }
        });

        testWidgets('the sheet shows each time and location whole at $width, ${scale}x', (
          tester,
        ) async {
          await _pump(
            tester,
            result: result,
            size: Size(width, 844),
            brightness: Brightness.light,
            scale: scale,
          );
          await tester.tap(find.text('Visiting chefs'));
          await tester.pumpAndSettle();
          final sheet = find.byType(BottomSheet);
          for (final text in [
            '11 AM to 2:30 PM',
            'The Cafe & Market at Crossroads',
            '4 PM to 7:30 PM',
            'Kitchen at Brick City',
          ]) {
            final inSheet = find.descendant(of: sheet, matching: find.text(text));
            expect(inSheet, findsOneWidget, reason: text);
            expect(_cut(tester, inSheet), isFalse, reason: text);
          }
        });
      }
    }
  });

  group('copy', () {
    Future<void> pumpState(WidgetTester tester, String state) => _pump(
      tester,
      result: _states[state]!,
      size: const Size(390, 844),
      brightness: Brightness.light,
      scale: 1,
    );

    testWidgets('available shows each chef with a time when known', (
      tester,
    ) async {
      await pumpState(tester, 'available');
      expect(find.text('KO-BQ'), findsOneWidget);
      // The time and the location are a line each.
      expect(find.text('11 AM to 2 PM'), findsOneWidget);
      expect(find.text('The Cafe & Market at Crossroads'), findsOneWidget);
      expect(find.text('4 PM to 7 PM'), findsOneWidget);
      expect(find.text('RITZ'), findsOneWidget);
      // No time published, so none is shown and none is invented.
      expect(find.text('Kitchen at Brick City'), findsOneWidget);
      expect(find.text('Menus unavailable'), findsNothing);
      expect(find.text('No visiting chefs today'), findsNothing);
    });

    testWidgets('a real quiet day says so and nothing else', (tester) async {
      await pumpState(tester, 'empty');
      expect(find.text('No visiting chefs today'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
      expect(find.text('Menus unavailable'), findsNothing);
    });

    testWidgets('a quiet day with an upcoming chef still shows only the title', (
      tester,
    ) async {
      await pumpState(tester, 'next');
      expect(find.text('No visiting chefs today'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });

    testWidgets('tomorrow gets no Next line either', (tester) async {
      await _pump(
        tester,
        result: Result(
          value: ChefCollection(
            data: const [],
            stale: false,
            availability: Availability.empty,
            next: UpcomingChef(
              date: DateTime.utc(2026, 10, 15),
              name: 'KO-BQ',
              locationName: 'RITZ',
            ),
          ),
          state: DataState.ok,
        ),
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.textContaining('Next:'), findsNothing);
    });

    testWidgets('the time is never cut, at 1x or 2x', (tester) async {
      for (final scale in [1.0, 2.0]) {
        await _pump(
          tester,
          result: _states['available']!,
          size: const Size(390, 844),
          brightness: Brightness.light,
          scale: scale,
        );
        final time = find.text('11 AM to 2 PM');
        expect(time, findsOneWidget, reason: 'at $scale');
        expect(_cut(tester, time), isFalse, reason: 'at $scale');
      }
    });

    testWidgets('the count pill stays in the header at every text size', (
      tester,
    ) async {
      for (final scale in [1.0, 1.5, 2.0]) {
        await _pump(
          tester,
          result: _states['available']!,
          size: const Size(390, 844),
          brightness: Brightness.light,
          scale: scale,
        );
        expect(find.text('3 today'), findsOneWidget, reason: 'at $scale');
        expect(find.byType(ScallopedBadge), findsNothing,
            reason: 'a phone gets the pill, not the 88px badge');
      }
    });

    testWidgets('from 600pt the hero is the scalloped badge, not the pill', (
      tester,
    ) async {
      await _pump(
        tester,
        result: _states['available']!,
        size: const Size(700, 900),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.byType(ScallopedBadge), findsOneWidget);
      expect(find.text('3 today'), findsNothing);
    });

    testWidgets('chefs that do not fit are counted as "+N more"', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < 6; i++)
          MenuItem(id: i, name: 'Chef $i', locationName: 'RITZ'),
      ];
      // the footer lives from 600pt, a phone header links instead
      await _pump(
        tester,
        result: Result(
          value: ChefCollection(data: many, stale: false),
          state: DataState.ok,
        ),
        size: const Size(700, 900),
        brightness: Brightness.light,
        scale: 2,
        height: 560,
      );
      expect(find.textContaining(RegExp(r'^\+\d+ more$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\+\d+ chefs?$')), findsNothing);

      // a phone previews three rows (phonePreviewRows) and counts none
      await _pump(
        tester,
        result: Result(
          value: ChefCollection(data: many, stale: false),
          state: DataState.ok,
        ),
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 2,
      );
      expect(find.byType(StatusRow), findsNWidgets(3));
      expect(find.textContaining(RegExp(r'^\+\d+')), findsNothing);
    });

    testWidgets('on a phone the header opens every chef', (tester) async {
      final handle = tester.ensureSemantics();
      final many = [
        for (var i = 0; i < 6; i++)
          MenuItem(id: i, name: 'Chef $i', locationName: 'RITZ'),
      ];
      await _pump(
        tester,
        result: Result(value: ChefCollection(data: many, stale: false), state: DataState.ok),
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      final link = find.bySemanticsLabel('Visiting chefs, shows all chefs');
      expect(link, findsOneWidget);
      expect(tester.getSemantics(link), isSemantics(isButton: true, hasTapAction: true));

      await tester.tap(find.text('Visiting chefs'));
      await tester.pumpAndSettle();
      expect(find.text('6 visiting chefs today'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a first run outage never says just now', (
      tester,
    ) async {
      // The fetch that failed just ran, so the result's own time is now.
      await _pump(
        tester,
        result: Result(
          value: const ChefCollection(
            data: [],
            stale: false,
            availability: Availability.unavailable,
          ),
          state: DataState.ok,
          fetchedAt: DateTime.now(),
        ),
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.text('Menus unavailable'), findsOneWidget);
      expect(find.text('Never updated'), findsNothing);
      expect(find.textContaining('just now'), findsNothing);
    });

    testWidgets('unavailable is not the empty state', (tester) async {
      await pumpState(tester, 'unavailable');
      expect(find.text('Menus unavailable'), findsOneWidget);
      expect(find.text('No visiting chefs today'), findsNothing);
      expect(find.text('Updated 5m ago'), findsNothing);
      expect(find.text('View on RIT'), findsOneWidget);
    });

    testWidgets('View on RIT is a 48pt link with a keyboard focus ring', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpState(tester, 'unavailable');
      final link = find.ancestor(
        of: find.text('View on RIT'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.text('View on RIT')),
        matchesSemantics(label: 'View on RIT', isLink: true, hasTapAction: true),
      );

      final ring = find.byKey(const ValueKey('focus-ring'));
      expect(ring, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring, findsOneWidget);
      semantics.dispose();
    });
  });

  group('+N more', () {
    // Eight chefs in a compact card at 1x: only some fit, so the pill shows.
    final many = [
      for (var i = 0; i < 8; i++)
        MenuItem(
          id: i,
          name: 'Chef $i',
          locationName: 'RITZ',
          cuisine: 'Cuisine $i',
          startsAt: DateTime.parse('2026-10-14T11:00:00-04:00'),
          endsAt: DateTime.parse('2026-10-14T14:00:00-04:00'),
        ),
    ];

    // the footer is the 600pt and wider layout now
    Future<void> pumpMany(WidgetTester tester) => _pump(
      tester,
      result: Result(
        value: ChefCollection(data: many, stale: false),
        state: DataState.ok,
      ),
      size: const Size(700, 900),
      brightness: Brightness.light,
      scale: 1,
      height: 560,
    );

    final pill = find.textContaining(RegExp(r'^\+\d+ more$'));
    final sheet = find.byType(BottomSheet);

    testWidgets('on a phone the header that replaces it is a 48px touch target', (tester) async {
      await _pump(
        tester,
        result: Result(value: ChefCollection(data: many, stale: false), state: DataState.ok),
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(pill, findsNothing);
      final band = find.ancestor(of: find.text('Visiting chefs'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(band).height, greaterThanOrEqualTo(48));
      // a tap at the edge of the band, off the text, still opens the sheet
      final rect = tester.getRect(band);
      await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
    });

    testWidgets('opens a sheet with every chef, and the close button closes it', (
      tester,
    ) async {
      await pumpMany(tester);
      expect(find.text('Chef 7'), findsNothing,
          reason: 'the card alone cannot show them all');

      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      // The sheet scrolls, so each is reached by scrolling, as a person would.
      for (var i = 0; i < 8; i++) {
        final chef = find.descendant(of: sheet, matching: find.text('Chef $i'));
        await tester.scrollUntilVisible(
          chef,
          80,
          scrollable: find.descendant(
            of: sheet,
            matching: find.byType(Scrollable),
          ),
        );
        expect(chef, findsOneWidget, reason: 'Chef $i should be in the sheet');
      }
      expect(
        find.descendant(of: sheet, matching: find.textContaining('Cuisine')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('8 visiting chefs today')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });

    for (final (mode, scale) in [(Brightness.light, 1.0), (Brightness.dark, 2.0)]) {
      final name = 'sheet_390x844_${mode.name}_${scale.toInt()}x';
      goldenWidgets('golden $name', (tester) async {
        await _pump(
          tester,
          result: Result(
            value: ChefCollection(data: many, stale: false),
            state: DataState.ok,
          ),
          size: const Size(390, 844),
          brightness: mode,
          scale: scale,
        );
        // a phone opens it from the header
        await tester.tap(find.text('Visiting chefs'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/visiting_chefs/$name.png'),
        );
      });
    }

    testWidgets('shows a 2px primary focus ring for the keyboard only', (
      tester,
    ) async {
      await pumpMany(tester);
      final scheme = Theme.of(tester.element(pill)).colorScheme;
      final ring = find.byKey(const ValueKey('focus-ring'));
      DecoratedBox box() => tester.widget<DecoratedBox>(ring);
      BorderSide side() =>
          ((box().decoration as ShapeDecoration).shape as OutlinedBorder).side;

      expect(ring, findsNothing, reason: 'no ring until the keyboard arrives');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring, findsOneWidget);
      expect(side().color, scheme.primary);
      expect(side().width, 2);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(ring, findsNothing, reason: 'focus has moved on');
    });

    testWidgets('a tap shows no ring', (tester) async {
      await pumpMany(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-ring')), findsNothing);
    });

    /// The footer's own box: the InkWell that the ring is drawn around.
    Finder footerBox() =>
        find.descendant(of: find.byType(MoreRow), matching: find.byType(InkWell));

    testWidgets('focusing moves nothing', (tester) async {
      await pumpMany(tester);
      final before = tester.getRect(footerBox());
      final rowLeft = tester
          .getRect(find.byIcon(Icons.restaurant_menu_rounded).first)
          .left;
      expect(before.left, greaterThanOrEqualTo(rowLeft - 12),
          reason: 'the footer sits in the card\'s content column');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.getRect(footerBox()), before,
          reason: 'the ring takes no room');
    });

    testWidgets('the focus ring sits 2px outside the footer, with a real gap', (
      tester,
    ) async {
      await pumpMany(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final boxRect = tester.getRect(footerBox());
      final ringRect = tester.getRect(find.byKey(const ValueKey('focus-ring')));

      // A border paints inside its box: the outer 2px is the ring, and the
      // 2px between it and the footer is the offset.
      expect(ringRect, boxRect.inflate(4),
          reason: 'ring outer edge = footer + 2px offset + 2px width');
      expect(ringRect.deflate(2), boxRect.inflate(2),
          reason: 'the ring starts 2px clear of the footer');
      expect(ringRect.height, lessThanOrEqualTo(48),
          reason: 'the ring stays inside the 48px touch band');
    });

    for (final (width, radius) in [(390.0, 24.0), (700.0, 30.0)]) {
      testWidgets('the sheet uses the ${radius.toInt()}px card radius at '
          '${width.toInt()}pt', (tester) async {
        await _pump(
          tester,
          result: Result(
            value: ChefCollection(data: many, stale: false),
            state: DataState.ok,
          ),
          size: Size(width, 900),
          brightness: Brightness.light,
          scale: 1,
          height: width >= 600 ? 560 : null,
        );
        await tester.tap(width >= 600 ? pill : find.text('Visiting chefs'));
        await tester.pumpAndSettle();
        final shape = tester.widget<BottomSheet>(sheet).shape!
            as RoundedRectangleBorder;
        final corners = shape.borderRadius as BorderRadius;
        expect(corners.topLeft.x, radius);
        expect(corners.topRight.x, radius);
        expect(corners.bottomLeft.x, 0);
      });
    }

    testWidgets('works from the keyboard and Esc dismisses', (tester) async {
      await pumpMany(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });

    testWidgets('is announced as a button that says what it does', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpMany(tester);
      // The label is exactly the visible "+N more", read once.
      final visible = tester.widget<Text>(pill).data!;
      expect(visible, matches(RegExp(r'^\+\d+ more$')));
      final node = find.bySemanticsLabel(visible);
      expect(node, findsOneWidget);
      expect(
        tester.getSemantics(node),
        isSemantics(isButton: true, hasTapAction: true),
      );

      await tester.tap(pill);
      await tester.pumpAndSettle();
      // The sheet's rows read as one node each.
      await tester.scrollUntilVisible(
        find.text('Chef 7'),
        80,
        scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
      );
      expect(
        find.bySemanticsLabel('Chef 7, 11 AM to 2 PM, RITZ'),
        findsOneWidget,
      );
      expect(find.textContaining('Cuisine'), findsNothing);
      handle.dispose();
    });
  });

  group('through the real ApiClient', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    Future<Result<Collection<MenuItem>>> load(
      Map<String, dynamic> body,
    ) async {
      final api = ApiClient(backend: _FixedBackend(body));
      return (await api.visitingChefs().toList()).last;
    }

    testWidgets('a first run outage does not say updated just now', (
      tester,
    ) async {
      // What LocalBackend sends when nothing ever held chefs: stale, no time.
      final result = (await tester.runAsync(
        () => load({
          'data': <dynamic>[],
          'stale': true,
          'last_updated': null,
          'availability': 'unavailable',
          'next': null,
        }),
      ))!;
      // The path really does stamp the response with now and call it stale.
      expect(result.state, DataState.stale);
      expect(result.fetchedAt, isNotNull);

      await _pump(
        tester,
        result: result,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.text('Menus unavailable'), findsOneWidget);
      expect(find.text('Never updated'), findsNothing);
      expect(find.textContaining('updated just now'), findsNothing);
    });

    testWidgets('rit.edu answering 200 with unrecognisable pages is unavailable '
        'and never updated', (tester) async {
      final dir = Directory.systemTemp.createTempSync('tigerhub-garbage');
      addTearDown(() => dir.deleteSync(recursive: true));
      JsonStore.overrideForTesting(dir);
      final tc = File('test/fixtures/tc_dining_all_empty_menus.json')
          .readAsStringSync();
      final backend = LocalBackend(
        upstream: Upstream(
          client: MockClient((request) async {
            if (request.url.host == 'tigercenter.rit.edu') {
              return http.Response(tc, 200);
            }
            return http.Response('<html><body>Redesigned!</body></html>', 200);
          }),
          maxRetries: 1,
        ),
        store: JsonStore.overrideForTestingInstance,
      );
      addTearDown(backend.close);

      final result = (await tester.runAsync(
        () async => (await ApiClient(backend: backend).visitingChefs().toList())
            .last,
      ))!;
      await _pump(
        tester,
        result: result,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.text('Menus unavailable'), findsOneWidget);
      expect(find.text('Never updated'), findsNothing);
      expect(find.textContaining('just now'), findsNothing,
          reason: 'the header may not claim an update');
      expect(find.text('No visiting chefs today'), findsNothing);
    });

    // The heading survives, the chef markup under it does not. This used to
    // be accepted as a quiet day and to advance "last updated".
    const restructured = {
      'div': '<div><a href="/x"><p class="h5">RITZ</p></a>'
          '<div data-id="26-1"><em>KO-BQ: 11:00 am - 2:00 pm</em></div></div>',
      'article': '<article><h3>RITZ</h3><article>KO-BQ</article></article>',
      'table': '<table><tr><td>RITZ</td><td>KO-BQ</td></tr></table>',
      'renamed attribute': '<a data-chef="26-1"><em>KO-BQ: 11:00 am - 2:00 pm'
          '</em></a>',
      // Nothing under the heading at all: not a quiet day, just no evidence.
      'no': '',
      'commented out': '<!-- <li><a chefid="26-1"><em>KO-BQ: 11:00 am - 2:00 pm'
          '</em></a></li> -->',
      'mixed empty and restructured':
          '<div><a href="/x"><p class="h5">RITZ</p></a><ul></ul></div>'
          '<div><a href="/y"><p class="h5">Gracie\'s</p></a>'
          '<section>KO-BQ</section></div>',
      'RIT empty marker on /menus': '<p class="no-visiting-chefs">None</p>',
    };
    for (final entry in restructured.entries) {
      testWidgets('a kept heading over ${entry.key} chef markup is unavailable '
          'and never updated', (tester) async {
        final dir = Directory.systemTemp.createTempSync('tigerhub-restyled');
        addTearDown(() => dir.deleteSync(recursive: true));
        JsonStore.overrideForTesting(dir);
        final tc = File('test/fixtures/tc_dining_all_empty_menus.json')
            .readAsStringSync();
        final backend = LocalBackend(
          upstream: Upstream(
            client: MockClient((request) async {
              if (request.url.host == 'tigercenter.rit.edu') {
                return http.Response(tc, 200);
              }
              if (request.url.path.endsWith('/dining/menus')) {
                return http.Response(
                  '<h2>Today\'s Visiting Chefs</h2>${entry.value}<script></script>',
                  200,
                );
              }
              // The schedule page is unreadable too, so nothing else can
              // vouch for a quiet day.
              return http.Response('<html><body>Redesigned!</body></html>', 200);
            }),
            maxRetries: 1,
          ),
          store: JsonStore.overrideForTestingInstance,
        );
        addTearDown(backend.close);

        final result = (await tester.runAsync(
          () async =>
              (await ApiClient(backend: backend).visitingChefs().toList()).last,
        ))!;
        await _pump(
          tester,
          result: result,
          size: const Size(390, 844),
          brightness: Brightness.light,
          scale: 1,
        );
        expect(find.text('Menus unavailable'), findsOneWidget);
        expect(find.text('Never updated'), findsNothing);
        expect(find.textContaining('just now'), findsNothing);
        expect(find.text('No visiting chefs today'), findsNothing);
      });
    }

    testWidgets('the schedule page positively listing today empty is a quiet day '
        'even when /menus shows nothing', (tester) async {
      final dir = Directory.systemTemp.createTempSync('tigerhub-quiet');
      addTearDown(() => dir.deleteSync(recursive: true));
      JsonStore.overrideForTesting(dir);
      final tc = File('test/fixtures/tc_dining_all_empty_menus.json')
          .readAsStringSync();
      final backend = LocalBackend(
        upstream: Upstream(
          client: MockClient((request) async {
            if (request.url.host == 'tigercenter.rit.edu') {
              return http.Response(tc, 200);
            }
            if (request.url.path.endsWith('/dining/menus')) {
              return http.Response(
                '<h2>Today\'s Visiting Chefs</h2><script></script>',
                200,
              );
            }
            return http.Response(
              '<div class="daily-visiting-chefs" id="day-2026-10-14">'
              '<h3>Today</h3><p class="no-visiting-chefs">None</p></div>'
              '<div class="daily-visiting-chefs" id="day-2026-10-15">'
              '<h3>Thu</h3><span>RITZ</span><ul><li><em>KO-BQ</em></li></ul>'
              '</div>',
              200,
            );
          }),
          maxRetries: 1,
        ),
        store: JsonStore.overrideForTestingInstance,
      );
      addTearDown(backend.close);

      final result = (await tester.runAsync(
        () async =>
            (await ApiClient(backend: backend).visitingChefs().toList()).last,
      ))!;
      await _pump(
        tester,
        result: result,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.text('No visiting chefs today'), findsOneWidget);
      expect(find.text('Menus unavailable'), findsNothing);
      expect(find.textContaining('Next:'), findsNothing);
    });

    testWidgets('a real source time is the age shown in the header', (
      tester,
    ) async {
      final at = DateTime.now().subtract(const Duration(minutes: 40)).toUtc();
      final result = (await tester.runAsync(
        () => load({
          'data': <dynamic>[],
          'stale': true,
          'last_updated': at.toIso8601String(),
          'availability': 'unavailable',
        }),
      ))!;
      await _pump(
        tester,
        result: result,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 1,
      );
      expect(find.text('updated 40m ago'), findsOneWidget);
      expect(find.text('Updated 40m ago'), findsNothing);
      expect(find.textContaining('just now'), findsNothing);
    });
  });

  // A 600pt+ cell bounds the card, and a compact one is 58% of the standard
  // height. Flutter fails any test that draws an overflow stripe, so pumping is
  // the assertion. Empty and unavailable must also stay centered, not pinned to
  // the top, at every text size.
  for (final scale in [1.0, 2.0]) {
    for (final state in _states.keys) {
      testWidgets('$state fits a bounded 700pt cell at ${scale}x', (
        tester,
      ) async {
        await _pump(
          tester,
          result: _states[state]!,
          size: const Size(700, 900),
          brightness: Brightness.dark,
          scale: scale,
          height: 325,
        );
        expect(tester.takeException(), isNull);
      });
    }
    for (final state in ['empty', 'next', 'unavailable']) {
      testWidgets('$state is centered in a 600pt+ cell at ${scale}x', (
        tester,
      ) async {
        await _pump(
          tester,
          result: _states[state]!,
          size: const Size(700, 900),
          brightness: Brightness.light,
          scale: scale,
          height: 560,
        );
        final card = tester.getRect(find.byKey(const ValueKey('card')));
        final mark = find.byIcon(
          state == 'unavailable'
              ? Icons.sync_problem_rounded
              : Icons.room_service_rounded,
        );
        final box = tester.getRect(mark);
        // Below the header and roughly mid-card, never hugging the top.
        expect(box.center.dy, greaterThan(card.top + card.height * 0.3),
            reason: 'the mark sits in the middle of the cell');
        expect(box.center.dx, closeTo(card.center.dx, 2),
            reason: 'and in the middle across');
      });
    }
  }

  testWidgets('a phone card is as tall as its content, and centers its message', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await _pump(
        tester,
        result: _states['unavailable']!,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: scale,
      );
      final card = tester.getRect(find.byKey(const ValueKey('card')));
      final mark = tester.getRect(find.byIcon(Icons.sync_problem_rounded));
      expect(mark.center.dx, closeTo(card.center.dx, 2), reason: 'at $scale');
      expect(tester.takeException(), isNull);
    }
  });

  const sizes = {
    '390x844': Size(390, 844),
    '430x932': Size(430, 932),
  };

  for (final size in sizes.entries) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        for (final state in _states.keys) {
          final name =
              '${state}_${size.key}_${brightness.name}_${scale.toInt()}x';
          // Generated on Linux, and font rasterising differs elsewhere.
          goldenWidgets('golden $name', (tester) async {
            await _pump(
              tester,
              result: _states[state]!,
              size: size.value,
              brightness: brightness,
              scale: scale,
            );
            await expectLater(
              find.byKey(const ValueKey('card')),
              matchesGoldenFile('goldens/visiting_chefs/$name.png'),
            );
          });
        }
      }
    }
  }
}
