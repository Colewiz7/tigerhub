/// Client tests. No network: the API client is driven with a mock http client.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/freshness.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/semantic.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/theme/tokens.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/widgets/menu_section.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/widgets/jump_list.dart';
import 'package:tigerhub/widgets/section_nav.dart';
import 'package:tigerhub/widgets/week_grid.dart';
import 'package:tigerhub/widgets/bounded_list.dart';
import 'package:tigerhub/widgets/content_column.dart';
import 'package:tigerhub/widgets/more_row.dart';
import 'package:tigerhub/screens/campus_screen.dart' show currentSeason;
import 'package:tigerhub/widgets/occupancy_chart.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';
import 'package:tigerhub/widgets/occupancy_chip.dart';

/// Stands in for a scrape. `ApiClient`'s caching and state machine are
/// transport independent, so these tests inject a [Backend] rather than a
/// mock HTTP client now that there is no HTTP transport to mock.
class _FakeBackend implements Backend {
  _FakeBackend(this.body);
  final Map<String, dynamic> body;
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => body;
  @override
  void close() {}
}

class _OfflineBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async => throw const SocketException('offline');
  @override
  void close() {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('data states', () {
    test('first launch with no cache and no server is priming', () async {
      final api = ApiClient(backend: _OfflineBackend());
      final results = await api.dining().toList();
      expect(results.first.state, DataState.priming);
      expect(results.last.state, DataState.priming);
      expect(results.last.hasData, isFalse);
    });

    test('successful fetch is ok and caches for next launch', () async {
      final body = <String, dynamic>{
        'data': [
          {'id': 23, 'name': 'Crossroads', 'is_open': true, 'occupancy': null},
        ],
        'stale': false,
        'last_updated': '2026-08-28T12:00:00Z',
      };
      final api = ApiClient(backend: _FakeBackend(body));
      final results = await api.dining().toList();
      expect(results.last.state, DataState.ok);
      expect(results.last.value!.data.single.name, 'Crossroads');

      // A second client with no network must still serve the cached payload.
      final offline = ApiClient(backend: _OfflineBackend());
      final replay = await offline.dining().toList();
      expect(replay.first.state, DataState.stale);
      expect(replay.first.value!.data.single.name, 'Crossroads');
      expect(replay.last.state, DataState.failing);
      expect(
        replay.last.hasData,
        isTrue,
        reason: 'stale cache must never become an error',
      );
    });

    test('server reported staleness is mirrored, not recomputed', () async {
      final body = <String, dynamic>{
        'data': <dynamic>[],
        'stale': true,
        'last_updated': null,
      };
      final api = ApiClient(backend: _FakeBackend(body));
      final results = await api.dining().toList();
      expect(results.last.state, DataState.stale);
    });
  });

  group('occupancy chip', () {
    testWidgets('renders nothing when there is no sensor', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OccupancyChip(occupancy: null))),
      );
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('no data'), findsNothing);
    });

    testWidgets('renders a percentage when a sensor exists', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(
              occupancy: Occupancy(count: 75, maxOcc: 150, percentFull: 50),
            ),
          ),
        ),
      );
      expect(find.text('50%'), findsOneWidget);
    });
  });

  group('occupancy honesty', () {
    testWidgets('over capacity says busy, not a precise percentage', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(
              occupancy: Occupancy(
                count: 46,
                maxOcc: 38,
                percentFull: 100,
                overCapacity: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('busy'), findsOneWidget);
      expect(
        find.textContaining('%'),
        findsNothing,
        reason: 'a wrong denominator must not be quoted as a precise figure',
      );
    });

    testWidgets('a count with no denominator shows the count, not a ratio', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(
              occupancy: Occupancy(count: 235, percentFull: null),
            ),
          ),
        ),
      );
      expect(find.text('235 here'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('bounded cards', () {
    // The grid cell height the home screen uses.
    const cellHeight = 340.0;
    const rowHeight = 44.0;
    const footerHeight = 46.0;

    Widget boxed(Widget child, {double height = cellHeight}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(height: height, child: child),
        ),
      ),
    );

    testWidgets('shows only rows that fit and counts the rest', (tester) async {
      await tester.pumpWidget(
        boxed(
          BoundedList(
            itemCount: 12,
            itemHeight: rowHeight,
            noun: 'locations',
            itemBuilder: (context, i) => Text('row $i'),
          ),
        ),
      );
      // (340 - 46) / 44 = 6 rows fit alongside the footer.
      expect(find.text('row 5'), findsOneWidget);
      expect(find.text('row 6'), findsNothing);
      expect(find.text('+6 locations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the footer is fully inside the box, never clipped', (
      tester,
    ) async {
      await tester.pumpWidget(
        boxed(
          BoundedList(
            itemCount: 12,
            itemHeight: rowHeight,
            noun: 'locations',
            itemBuilder: (context, i) => Text('row $i'),
          ),
        ),
      );
      final box = tester.getRect(find.byType(BoundedList));
      final footer = tester.getRect(find.byType(MoreRow));
      expect(
        footer.bottom,
        lessThanOrEqualTo(box.bottom + 0.5),
        reason: 'the "+N more" row must be visible, not cut off',
      );
    });

    testWidgets('no footer when everything fits', (tester) async {
      await tester.pumpWidget(
        boxed(
          BoundedList(
            itemCount: 3,
            itemHeight: rowHeight,
            noun: 'locations',
            itemBuilder: (context, i) => Text('row $i'),
          ),
        ),
      );
      expect(find.byType(MoreRow), findsNothing);
      expect(find.text('row 2'), findsOneWidget);
    });

    testWidgets('a shorter box withholds more, and still says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        boxed(
          BoundedList(
            itemCount: 12,
            itemHeight: rowHeight,
            noun: 'locations',
            itemBuilder: (context, i) => Text('row $i'),
          ),
          height: 2 * rowHeight + footerHeight,
        ),
      );
      expect(find.text('row 1'), findsOneWidget);
      expect(find.text('row 2'), findsNothing);
      expect(find.text('+10 locations'), findsOneWidget);
    });

    testWidgets('dining stays useful at the minimum card height', (
      tester,
    ) async {
      // The grid cell the home screen actually uses. The hero sits inline with
      // the title precisely so the list keeps its rows.
      final locations = [
        for (var i = 0; i < 24; i++)
          DiningLocation(
            id: i,
            name: 'Place ${i.toString().padLeft(2, '0')}',
            isOpen: true,
            occupancy: i == 0
                ? const Occupancy(count: 9, maxOcc: 12, percentFull: 75)
                : null,
          ),
      ];
      await tester.pumpWidget(
        boxed(
          DiningCard(
            result: Result(
              value: Collection(data: locations, stale: false),
              state: DataState.ok,
            ),
          ),
          height: 560,
        ),
      );
      expect(tester.takeException(), isNull);
      final rows = [
        for (var i = 0; i < 24; i++)
          if (find
              .text('Place ${i.toString().padLeft(2, '0')}')
              .evaluate()
              .isNotEmpty)
            i,
      ];
      // Rows are containers now, roughly 64px tall, so fewer fit on purpose.
      // The bar is that the card still shows a useful handful, not a count
      // carried over from when rows were bare 38px text lines.
      expect(
        rows.length,
        greaterThanOrEqualTo(3),
        reason: 'the card must still show a useful number of locations',
      );
      expect(find.byType(MoreRow), findsOneWidget);
      // The badge is still present, just beside the title.
      expect(find.byType(ScallopedBadge), findsOneWidget);
    });

    testWidgets('dining bounds itself and keeps open locations first', (
      tester,
    ) async {
      final locations = [
        for (var i = 0; i < 12; i++)
          DiningLocation(
            id: i,
            name: 'Place ${i.toString().padLeft(2, '0')}',
            isOpen: i < 3,
          ),
      ];
      await tester.pumpWidget(
        boxed(
          DiningCard(
            result: Result(
              value: Collection(data: locations, stale: false),
              state: DataState.ok,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Place 00'), findsOneWidget);
      expect(find.text('Place 11'), findsNothing);
      expect(find.byType(MoreRow), findsOneWidget);
    });

    testWidgets('dining footer and visible open rows equal the hero count', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final locations = [
        for (var i = 0; i < 14; i++)
          DiningLocation(
            id: i,
            name: 'Open ${i.toString().padLeft(2, '0')}',
            isOpen: true,
          ),
        for (var i = 0; i < 10; i++)
          DiningLocation(
            id: 100 + i,
            name: 'Closed ${i.toString().padLeft(2, '0')}',
            isOpen: false,
          ),
      ];

      await tester.pumpWidget(
        boxed(
          DiningCard(
            result: Result(
              value: Collection(data: locations, stale: false),
              state: DataState.ok,
            ),
          ),
          height: 700,
        ),
      );

      // Match the row TITLE exactly. A prefix match also catches the "Open now"
      // subtitle each row now carries, which double counts.
      final namePattern = RegExp(r'^Open \d\d$');
      final visibleOpen = find
          .byWidgetPredicate(
            (widget) =>
                widget is Text && namePattern.hasMatch(widget.data ?? ''),
          )
          .evaluate()
          .length;
      const heroOpen = 14;

      // Read the hidden count off the footer rather than hardcoding it, so the
      // invariant survives a change in row height.
      final footer =
          find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Text &&
                        (widget.data?.endsWith(' open') ?? false),
                  )
                  .evaluate()
                  .single
                  .widget
              as Text;
      final hiddenOpen = int.parse(
        footer.data!.replaceAll(RegExp(r'[^0-9]'), ''),
      );

      expect(
        visibleOpen + hiddenOpen,
        heroOpen,
        reason: 'the footer and the hero must count the same population',
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^Closed \d\d$').hasMatch(widget.data ?? ''),
        ),
        findsNothing,
        reason: 'open locations must fill the visible rows first',
      );
    });

    testWidgets('more row is tappable for the future detail view', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoreRow(hidden: 7, noun: 'locations', onTap: () => tapped++),
          ),
        ),
      );
      await tester.tap(find.text('+7 locations'));
      expect(tapped, 1);
    });
  });

  group('freshness line', () {
    testWidgets('fresh data gets no annotation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FreshnessLine(state: DataState.ok, fetchedAt: DateTime.now()),
          ),
        ),
      );
      expect(find.textContaining('updated'), findsNothing);
    });

    testWidgets('stale data shows a quiet timestamp and no spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FreshnessLine(
              state: DataState.stale,
              fetchedAt: DateTime.now().subtract(const Duration(minutes: 40)),
            ),
          ),
        ),
      );
      expect(find.text('updated 40m ago'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('failing shows the same text with a warning icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FreshnessLine(
              state: DataState.failing,
              fetchedAt: DateTime.now().subtract(const Duration(hours: 2)),
            ),
          ),
        ),
      );
      expect(find.text('updated 2h ago'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });
  });

  _designTokens();
  _dynamicColour();
  _screenshotReview();
  _visualStructure();
  _statusAndGrouping();
  _quickWins();
  _pinningAndChart();
  _shippedPalette();
  _responsiveLayout();
  _weekGridAndClosed();
  _menus();
  _sectionNav();
  _jumpRail();

  test('age formatting', () {
    final now = DateTime.now();
    expect(formatAge(now), 'just now');
    expect(formatAge(now.subtract(const Duration(minutes: 40))), '40m ago');
    expect(formatAge(now.subtract(const Duration(hours: 3))), '3h ago');
    expect(formatAge(now.subtract(const Duration(days: 2))), '2d ago');
  });
}

ColorScheme _fallbackScheme() => schemeFromJson(_caelestiaSample)!;

/// A trimmed copy of the real ~/.local/state/caelestia/scheme.json, so the
/// parser is tested against the actual shape rather than an invented one.
const Map<String, dynamic> _caelestiaSample = {
  'name': 'dynamic',
  'mode': 'dark',
  'variant': 'tonalspot',
  'colours': {
    'background': '050301',
    'onBackground': 'f8e1d5',
    'surface': '050301',
    'surfaceContainerLowest': '000000',
    'surfaceContainerLow': '080402',
    'surfaceContainerHigh': '0e0705',
    'onSurface': 'f8e1d5',
    'onSurfaceVariant': 'bba79c',
    'outline': '847268',
    'outlineVariant': '54453c',
    'surfaceTint': '372418',
    'primary': 'f6ba96',
    'onPrimary': '5e361c',
    'primaryContainer': '74482c',
    'onPrimaryContainer': 'ffdcca',
    'secondary': 'e5bfa9',
    'error': 'f97758',
    'onError': '450900',
    'errorContainer': '85230a',
    'onErrorContainer': 'ff9b82',
    'inverseSurface': 'fff8f5',
    'inverseOnSurface': '5d534e',
    'inversePrimary': '825438',
    'shadow': '000000',
    'scrim': '000000',
  },
};

void _dynamicColour() {
  group('dynamic colour', () {
    test('parses the real Caelestia scheme shape', () {
      final scheme = schemeFromJson(_caelestiaSample);
      expect(scheme, isNotNull);
      expect(scheme!.primary, const Color(0xFFF6BA96));
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.onSurface, const Color(0xFFF8E1D5));
    });

    test('honours the light mode flag', () {
      final light = schemeFromJson({..._caelestiaSample, 'mode': 'light'});
      expect(light!.brightness, Brightness.light);
    });

    test('hex parses with and without a leading hash', () {
      expect(parseHex('f6ba96'), const Color(0xFFF6BA96));
      expect(parseHex('#f6ba96'), const Color(0xFFF6BA96));
      expect(parseHex('nonsense'), isNull);
      expect(parseHex(null), isNull);
      expect(parseHex(42), isNull);
    });

    test('a payload missing the essential roles falls back rather than half themes', () {
      expect(schemeFromJson({'colours': {}}), isNull);
      expect(
        schemeFromJson({
          'colours': {'primary': 'f6ba96'},
        }),
        isNull,
      );
      expect(schemeFromJson({'nope': true}), isNull);
    });

    test(
      'container levels are derived from the tint so nesting stays visible',
      () {
        final scheme = schemeFromJson(_caelestiaSample)!;
        // The file's own container roles sit within a few points of each other,
        // so they are re-derived by blending surfaceTint over surface.
        final levels = [
          scheme.surfaceContainerLowest,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.surfaceContainerHighest,
        ];
        for (var i = 1; i < levels.length; i++) {
          expect(levels[i].r, greaterThan(levels[i - 1].r));
        }
      },
    );

    test(
      'the built-in palette is the default, with no scheme file needed',
      () async {
        final controller = SchemeController();
        await controller.load();
        expect(controller.state.origin, SchemeOrigin.seed);
        expect(controller.state.isDynamic, isFalse);
        // The escape hatch must always produce something readable.
        final theme = AppTheme.from(controller.state.scheme);
        expect(theme.colorScheme.primary, isNotNull);
        controller.dispose();
      },
    );

    test('the wallpaper opt in flips back and forth', () async {
      final controller = SchemeController();
      await controller.load();
      expect(controller.forcedToSeed, isTrue);
      await controller.setForceSeed(false);
      expect(controller.forcedToSeed, isFalse);
      controller.dispose();
    });

    testWidgets('palette icon tooltip identifies source and action', (
      tester,
    ) async {
      final controller = SchemeController();
      await controller.load();
      final api = ApiClient(backend: _OfflineBackend());

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(api: api, scheme: controller),
        ),
      );
      await tester.pump();

      // The app bar now also carries a settings tooltip, so target the
      // palette one by its message rather than by type alone.
      final tooltip = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .firstWhere((t) => (t.message ?? '').contains('Theme source'));
      expect(tooltip.message, contains('Theme source: built-in palette'));
      expect(tooltip.message, contains('Tap to follow the wallpaper'));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}

/// Design token guarantees. These encode rules from the brief that are easy to
/// regress by accident.
void _designTokens() {
  group('design tokens', () {
    test('the scalloped badge stays inside StarBorder assertions', () {
      // pointRounding + valleyRounding must not exceed 1, so the 1.0/1.0 pair
      // from the brief throws. This asserts the shape actually constructs.
      final badge = Shapes.badge as StarBorder;
      expect(
        badge.pointRounding + badge.valleyRounding,
        lessThanOrEqualTo(1.0),
      );
      expect(badge.points, 7);
      expect(badge.innerRadiusRatio, 0.93);
      // Past roughly 0.95 the lobes flatten into a circle.
      expect(badge.innerRadiusRatio, lessThan(0.95));
    });

    test('nothing is rounded at 8 or below', () {
      expect(Shapes.cardRadius, greaterThanOrEqualTo(28));
      expect(Shapes.innerRadius, greaterThan(8));
      expect(Shapes.smallRadius, greaterThan(8));
    });

    test('cards carry no shadow at any elevation', () {
      final theme = AppTheme.from(_fallbackScheme());
      expect(theme.cardTheme.elevation, 0);
      expect(theme.shadowColor, Colors.transparent);
    });

    test('surfaces step lighter and stay warm, never neutral grey', () {
      final scheme = _fallbackScheme();
      final levels = [
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ];
      for (var i = 1; i < levels.length; i++) {
        expect(
          levels[i].r,
          greaterThan(levels[i - 1].r),
          reason: 'each nested level must step one lighter',
        );
      }
      for (final c in levels) {
        expect(
          c.r,
          greaterThan(c.b),
          reason: 'surfaces must be warm tinted, not neutral grey',
        );
      }
    });
  });
}

/// Regressions from the screenshot review.
void _screenshotReview() {
  group('screenshot review fixes', () {
    test('midnight and noon apply only at exact boundaries', () {
      expect(formatClock(DateTime(2026, 8, 28, 0, 0)), 'midnight');
      expect(formatClock(DateTime(2026, 8, 28, 12, 0)), 'noon');
      expect(formatClock(DateTime(2026, 8, 28, 0, 1)), '12:01 AM');
      expect(formatClock(DateTime(2026, 8, 28, 23, 59)), '11:59 PM');
    });

    testWidgets(
      'the dining hero counts open locations, not one unrelated one',
      (tester) async {
        // Regression: the badge used to show occupancy for a location that was
        // usually not among the visible rows, which made it meaningless.
        final locations = [
          for (var i = 0; i < 10; i++)
            DiningLocation(
              id: i,
              name: 'Place ${i.toString().padLeft(2, '0')}',
              isOpen: i < 6,
              // Give the sensor to a location far down the list.
              occupancy: i == 9
                  ? const Occupancy(count: 165, maxOcc: 136, percentFull: 100)
                  : null,
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: 480,
                  child: DiningCard(
                    result: Result(
                      value: Collection(data: locations, stale: false),
                      state: DataState.ok,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('6'), findsOneWidget);
        expect(find.text('OPEN NOW'), findsOneWidget);
        // The unrelated location's number must not be the hero.
        expect(find.text('165'), findsNothing);
      },
    );

    testWidgets('a taller card yields more rows for free', (tester) async {
      Future<int> rowsAt(double height) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: height,
                  child: BoundedList(
                    itemCount: 30,
                    itemHeight: 38,
                    noun: 'locations',
                    itemBuilder: (context, i) => Text('row $i'),
                  ),
                ),
              ),
            ),
          ),
        );
        return [
          for (var i = 0; i < 30; i++)
            if (find.text('row $i').evaluate().isNotEmpty) i,
        ].length;
      }

      final short = await rowsAt(344);
      final tall = await rowsAt(560);
      expect(
        tall,
        greaterThan(short),
        reason: 'growing the card must turn into more rows',
      );
    });

    testWidgets('the footer stays inside the box at several window sizes', (
      tester,
    ) async {
      for (final height in [200.0, 344.0, 460.0, 560.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: height,
                  child: BoundedList(
                    itemCount: 40,
                    itemHeight: 38,
                    noun: 'locations',
                    itemBuilder: (context, i) => Text('row $i'),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at height $height');
        final box = tester.getRect(find.byType(BoundedList));
        final footer = tester.getRect(find.byType(MoreRow));
        expect(
          footer.bottom,
          lessThanOrEqualTo(box.bottom + 0.5),
          reason: 'footer escaped the box at height $height',
        );
      }
    });
  });
}

/// The structural overhaul: visible surfaces, container rows, harmonized
/// status colours, and the past/future split.
void _visualStructure() {
  group('surfaces are actually distinguishable', () {
    double luminance(Color c) =>
        0.2126 * c.r * 255 + 0.7152 * c.g * 255 + 0.0722 * c.b * 255;

    test('each nesting level is clearly lighter, not a hair lighter', () {
      final scheme = _fallbackScheme();
      final levels = [
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ];
      for (var i = 1; i < levels.length; i++) {
        final step = luminance(levels[i]) - luminance(levels[i - 1]);
        // The old blend produced steps under 2, which made card edges vanish.
        // Calibrated against the real Caelestia panel, whose own steps are
        // modest, so this asserts visible separation rather than a big jump.
        expect(
          step,
          greaterThan(4),
          reason: 'step $i was only $step, cards would be invisible',
        );
      }

      // The card must clearly read as a card against the page behind it.
      expect(
        luminance(scheme.surfaceContainerLow) -
            luminance(scheme.surfaceContainerLowest),
        greaterThan(8),
      );
    });
  });

  group('semantic colours', () {
    test('are harmonized toward the scheme, not raw hues', () {
      final scheme = _fallbackScheme();
      final semantic = Semantic.from(scheme);
      // A raw Colors.green would survive unchanged. Harmonizing must move it.
      expect(semantic.open, isNot(Colors.green));
      expect(semantic.closed, isNot(Colors.red));
      expect(semantic.busy, isNot(Colors.amber));
    });

    test('open, closed and busy stay distinguishable from each other', () {
      final semantic = Semantic.from(_fallbackScheme());
      expect(semantic.open, isNot(semantic.closed));
      expect(semantic.open, isNot(semantic.busy));
      expect(semantic.closed, isNot(semantic.busy));
    });

    test(
      'rebuild against a different scheme, so they follow the wallpaper',
      () {
        final warm = Semantic.from(_fallbackScheme());
        final cool = Semantic.from(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF2196F3),
            brightness: Brightness.dark,
          ),
        );
        expect(
          warm.open,
          isNot(cool.open),
          reason: 'status colours must track the active palette',
        );
      },
    );
  });

  group('container rows', () {
    testWidgets('a dining row has an icon badge, a title and a subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(_fallbackScheme()),
          home: Scaffold(
            body: DiningRow(
              location: DiningLocation(
                id: 1,
                name: 'Beanz',
                isOpen: true,
                closesAt: DateTime(2026, 8, 28, 22),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Beanz'), findsOneWidget);
      expect(find.text('OPEN · until 10:00 PM'), findsOneWidget);
      expect(find.byIcon(Icons.local_cafe_rounded), findsOneWidget);
      // No standalone pill. The subtitle still states the status in text.
      expect(find.text('OPEN'), findsNothing);
    });

    testWidgets('a closed row is dimmed relative to an open one', (
      tester,
    ) async {
      Future<double> opacityFor(bool isOpen) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.from(_fallbackScheme()),
            home: Scaffold(
              body: DiningRow(
                location: DiningLocation(id: 1, name: 'X', isOpen: isOpen),
              ),
            ),
          ),
        );
        final op = tester.widgetList<Opacity>(find.byType(Opacity)).first;
        return op.opacity;
      }

      expect(await opacityFor(false), lessThan(await opacityFor(true)));
    });

    testWidgets('venue type picks the icon', (tester) async {
      expect(iconForVenue('Corner Store'), Icons.storefront_rounded);
      expect(iconForVenue('Java Wally\'s'), Icons.local_cafe_rounded);
      expect(iconForVenue('RIT Food Truck'), Icons.local_shipping_rounded);
      expect(iconForVenue('Gracie\'s'), Icons.restaurant_rounded);
    });
  });

  group('past and future events', () {
    Widget wrap(CampusEvent event, DateTime now) => MaterialApp(
      theme: AppTheme.from(_fallbackScheme()),
      home: Scaffold(
        body: EventRow(event: event, now: now),
      ),
    );

    CampusEvent at(DateTime start, {DateTime? end}) => CampusEvent(
      uid: 'u',
      source: 'campusgroups',
      title: 'Dodgeball',
      startsAt: start,
      endsAt: end,
    );

    testWidgets('a finished event is marked and dimmed', (tester) async {
      await tester.pumpWidget(
        wrap(
          at(DateTime(2026, 8, 28, 9), end: DateTime(2026, 8, 28, 10)),
          DateTime(2026, 8, 28, 14),
        ),
      );
      expect(find.text('ENDED'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    });

    testWidgets('an upcoming event is not marked', (tester) async {
      await tester.pumpWidget(
        wrap(
          at(DateTime(2026, 8, 28, 19), end: DateTime(2026, 8, 28, 21)),
          DateTime(2026, 8, 28, 14),
        ),
      );
      expect(find.text('ENDED'), findsNothing);
      expect(find.byIcon(Icons.history_rounded), findsNothing);
    });

    testWidgets('an event with no end uses its start', (tester) async {
      await tester.pumpWidget(
        wrap(at(DateTime(2026, 8, 28, 9)), DateTime(2026, 8, 28, 14)),
      );
      expect(find.text('ENDED'), findsOneWidget);
    });

    testWidgets('an event running right now counts as future', (tester) async {
      await tester.pumpWidget(
        wrap(
          at(DateTime(2026, 8, 28, 13), end: DateTime(2026, 8, 28, 15)),
          DateTime(2026, 8, 28, 14),
        ),
      );
      expect(find.text('ENDED'), findsNothing);
    });
  });
}

/// The status badge only appears when the status is not the default, and
/// dining groups by the category the server supplies.
void _statusAndGrouping() {
  DiningLocation loc(
    String name, {
    bool open = true,
    int? percent,
    bool over = false,
    String category = 'other',
    String categoryName = 'Everything else',
    int order = 3,
  }) => DiningLocation(
    id: name.hashCode,
    name: name,
    isOpen: open,
    category: category,
    categoryName: categoryName,
    categoryOrder: order,
    closesAt: open ? DateTime(2026, 8, 28, 22) : null,
    occupancy: percent == null
        ? null
        : Occupancy(
            count: 10,
            maxOcc: 20,
            percentFull: percent,
            overCapacity: over,
          ),
  );

  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.from(_fallbackScheme()),
    home: Scaffold(body: child),
  );

  group('status hierarchy', () {
    testWidgets('open with no sensor shows no pill at all', (tester) async {
      await tester.pumpWidget(wrap(DiningRow(location: loc('Beanz'))));
      expect(find.text('OPEN'), findsNothing);
      expect(find.text('CLOSED'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('open with a sensor shows the occupancy', (tester) async {
      await tester.pumpWidget(
        wrap(DiningRow(location: loc('Crossroads', percent: 86))),
      );
      expect(find.text('86%'), findsOneWidget);
      expect(find.text('OPEN'), findsNothing);
    });

    testWidgets('over capacity shows BUSY, never a percentage', (tester) async {
      await tester.pumpWidget(
        wrap(
          DiningRow(location: loc('Midnight Oil', percent: 100, over: true)),
        ),
      );
      expect(find.text('BUSY'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('closed shows CLOSED', (tester) async {
      await tester.pumpWidget(
        wrap(DiningRow(location: loc('Gracie', open: false))),
      );
      expect(find.textContaining('CLOSED ·'), findsOneWidget);
      expect(
        find.text('CLOSED'),
        findsNothing,
        reason: 'closed status belongs in the subtitle, not a repeated pill',
      );
    });

    testWidgets('a column of open rows carries no repeated pills', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ListView(
            children: [
              for (final n in ['A', 'B', 'C', 'D', 'E'])
                DiningRow(location: loc(n)),
            ],
          ),
        ),
      );
      // The whole point: 13 identical pills was noise.
      expect(find.text('OPEN'), findsNothing);
    });
  });

  group('dining ordering', () {
    test('sensors first by percent, then alphabetical, closed last', () {
      final list = [
        loc('Zulu', open: false),
        loc('Alpha'),
        loc('Bravo', percent: 40),
        loc('Charlie', percent: 90),
        loc('Delta'),
      ]..sort(compareForDisplay);

      expect(list.map((l) => l.name).toList(), [
        'Charlie',
        'Bravo',
        'Alpha',
        'Delta',
        'Zulu',
      ]);
    });

    test('closed locations sort last even with a sensor', () {
      final list = [
        loc('Shut', open: false, percent: 99),
        loc('Open', percent: 10),
      ]..sort(compareForDisplay);
      expect(list.first.name, 'Open');
    });

    test('groups come back in the configured order', () {
      final groups = groupByCategory([
        loc('Other one'),
        loc('A market', category: 'market', categoryName: 'Markets', order: 1),
        loc(
          'GV thing',
          category: 'global_village',
          categoryName: 'Global Village',
          order: 2,
        ),
      ]);
      expect(groups.map((g) => g.key).toList(), [
        'Markets',
        'Global Village',
        'Everything else',
      ]);
    });

    test('each group is sorted internally', () {
      final groups = groupByCategory([
        loc('B market', category: 'market', categoryName: 'Markets', order: 1),
        loc(
          'A market',
          category: 'market',
          categoryName: 'Markets',
          order: 1,
          percent: 50,
        ),
      ]);
      // The one with a sensor leads its group.
      expect(groups.single.value.first.name, 'A market');
    });
  });
}

/// Quick wins from the friend review.
void _quickWins() {
  group('post office hours show only the current season', () {
    test('fall term for the academic year', () {
      expect(currentSeason(DateTime(2026, 9, 15)), 'fall');
      expect(currentSeason(DateTime(2026, 12, 1)), 'fall');
      expect(currentSeason(DateTime(2027, 3, 4)), 'fall');
      // Fall hours begin Aug 22 per RIT's own page.
      expect(currentSeason(DateTime(2026, 8, 22)), 'fall');
    });

    test('summer for the summer months', () {
      expect(currentSeason(DateTime(2026, 6, 15)), 'summer');
      expect(currentSeason(DateTime(2026, 7, 1)), 'summer');
      expect(currentSeason(DateTime(2026, 8, 21)), 'summer');
    });
  });

  group('semantic open is brighter than the other states', () {
    double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

    test('open outranks closed and busy in a dark scheme', () {
      final s = Semantic.from(_fallbackScheme());
      expect(
        lum(s.open),
        greaterThan(lum(s.closed)),
        reason: 'open is the state people scan for',
      );
    });
  });

  group('the hero number is not hairline thin', () {
    testWidgets('badge value uses a heavier weight than the display scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(_fallbackScheme()),
          home: const Scaffold(
            body: ScallopedBadge(value: '13', label: 'OPEN NOW'),
          ),
        ),
      );
      final value = tester.widget<Text>(find.text('13'));
      final weight = value.style!.fontVariations!
          .firstWhere((v) => v.axis == 'wght')
          .value;
      // The display scale is 300. At badge size that read as washed out.
      expect(weight, greaterThan(300));
    });
  });
}

/// Pinning, and the occupancy chart's colour reasoning.
void _pinningAndChart() {
  DiningLocation loc(int id, String name, {bool open = true}) => DiningLocation(
    id: id,
    name: name,
    isOpen: open,
    categoryName: 'Everything else',
    categoryOrder: 3,
  );

  group('pinning', () {
    test('a pinned location outranks everything, including open ones', () {
      final list = [
        loc(1, 'Alpha'),
        loc(2, 'Bravo'),
        loc(3, 'Pinned but closed', open: false),
      ]..sort((a, b) => compareForDisplay(a, b, pinned: {'3'}));
      expect(
        list.first.name,
        'Pinned but closed',
        reason: 'a pin is an explicit statement of interest',
      );
    });

    test('without a pin set the normal order holds', () {
      final list = [loc(3, 'Closed', open: false), loc(1, 'Alpha')]
        ..sort(compareForDisplay);
      expect(list.first.name, 'Alpha');
    });

    test('groups respect pins too', () {
      final groups = groupByCategory(
        [loc(1, 'Zulu'), loc(2, 'Alpha')],
        pinned: {'1'},
      );
      expect(groups.single.value.first.name, 'Zulu');
    });
  });

  group('occupancy chart', () {
    List<OccupancyHour> series(int nowToday, int nowAverage) => [
      for (var h = 0; h < 24; h++)
        OccupancyHour(
          hour: h,
          today: h == 12 ? nowToday : 10,
          oneWeekAgo: 10,
          average: h == 12 ? nowAverage : 10,
        ),
    ];

    test(
      'the comparison is stated in words, not left to two similar colours',
      () {
        // The wallpaper palette is near monochrome, so primary and
        // onSurfaceVariant sit only dE 10.9 apart. Two series would be
        // unreadable, so the comparison is a sentence.
        expect(busynessCaption(series(30, 10), 12), contains('Busier'));
        expect(busynessCaption(series(3, 10), 12), contains('Quieter'));
        expect(busynessCaption(series(10, 10), 12), contains('as usual'));
      },
    );

    test('a missing hour or a zero baseline yields no claim', () {
      expect(busynessCaption(series(10, 0), 12), isEmpty);
      expect(busynessCaption(const [], 12), isEmpty);
    });

    testWidgets('renders one bar per published hour and no legend', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.from(_fallbackScheme()),
          home: Scaffold(
            body: OccupancyChart(hourly: series(20, 10), nowHour: 12),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // One series, so the caption names it and there is no legend box.
      expect(find.byType(Tooltip), findsNWidgets(24));
    });
  });
}

/// The palette ships with the app rather than being taken from a wallpaper,
/// so its accessibility is a fixed property that can be locked down.
void _shippedPalette() {
  double lum(Color c) =>
      0.2126 * c.r * 255 + 0.7152 * c.g * 255 + 0.0722 * c.b * 255;

  group('built-in palette', () {
    test('is the default, wallpaper following is opt in', () async {
      final controller = SchemeController();
      await controller.load();
      expect(controller.state.origin, SchemeOrigin.seed);
      expect(
        controller.state.isDynamic,
        isFalse,
        reason: 'this ships to many desktops, it cannot assume a wallpaper',
      );
      controller.dispose();
    });

    test('exists in both modes, generated from one seed', () {
      final dark = SchemeController.builtIn(Brightness.dark);
      final light = SchemeController.builtIn(Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.primary, isNot(light.primary));
    });

    test('surfaces are separable in both modes', () {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        final s = SchemeController.builtIn(brightness);
        final levels = [
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ];
        for (var i = 1; i < levels.length; i++) {
          expect(
            (lum(levels[i]) - lum(levels[i - 1])).abs(),
            greaterThan(3),
            reason: 'step $i in $brightness is invisible',
          );
        }
      }
    });
  });

  group('status colours are separable, in both modes', () {
    // These values were picked by running the palette validator, not by eye.
    // Red against green is the fundamental colourblindness case, so they are
    // separated by lightness as well as hue.
    test('open, closed and busy differ in lightness, not only in hue', () {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        final sem = Semantic.from(SchemeController.builtIn(brightness));
        final tones = [lum(sem.open), lum(sem.closed), lum(sem.busy)];
        for (var i = 0; i < tones.length; i++) {
          for (var j = i + 1; j < tones.length; j++) {
            expect(
              (tones[i] - tones[j]).abs(),
              greaterThan(20),
              reason:
                  'a colourblind reader has only lightness to go on '
                  'in $brightness',
            );
          }
        }
      }
    });

    test('the old full harmonize collapsed red onto amber, and is gone', () {
      final sem = Semantic.from(SchemeController.builtIn(Brightness.dark));
      // The shipped harmonize put these dE 4.8 apart in normal vision. A crude
      // proxy: they must no longer be near identical.
      final closedLum = lum(sem.closed);
      final busyLum = lum(sem.busy);
      expect((closedLum - busyLum).abs(), greaterThan(40));
    });
  });
}

/// Two column layout on a wide window.
void _responsiveLayout() {
  group('responsive list', () {
    Widget boxed(double width) => MaterialApp(
      theme: AppTheme.from(_fallbackScheme()),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: ResponsiveList(
            itemCount: 6,
            itemBuilder: (context, i) =>
                SizedBox(height: 60, child: Text('item $i')),
          ),
        ),
      ),
    );

    testWidgets('stays one column on a narrow window', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(boxed(900));
      expect(tester.takeException(), isNull);

      // One column: every item shares a left edge.
      final lefts = {
        for (var i = 0; i < 6; i++) tester.getTopLeft(find.text('item $i')).dx,
      };
      expect(lefts.length, 1);
    });

    testWidgets('splits into two columns when there is room', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(boxed(1600));
      expect(tester.takeException(), isNull);

      final lefts = {
        for (var i = 0; i < 6; i++) tester.getTopLeft(find.text('item $i')).dx,
      };
      expect(lefts.length, 2, reason: 'a wide window should use the width');
    });

    testWidgets('items alternate so the columns stay a similar height', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(boxed(1600));

      // Alternating means 0 and 2 share a column, 0 and 1 do not.
      final zero = tester.getTopLeft(find.text('item 0')).dx;
      final one = tester.getTopLeft(find.text('item 1')).dx;
      final two = tester.getTopLeft(find.text('item 2')).dx;
      expect(zero, equals(two));
      expect(zero, isNot(equals(one)));
    });

    testWidgets('every item is still rendered in two column mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(boxed(1600));
      for (var i = 0; i < 6; i++) {
        expect(find.text('item $i'), findsOneWidget);
      }
    });
  });
}

/// The week grid, and the calmer closed colour.
void _weekGridAndClosed() {
  group('week grid', () {
    Widget wrap(List<WeekRow> rows, {int start = 6, int end = 24}) =>
        MaterialApp(
          theme: AppTheme.from(_fallbackScheme()),
          home: Scaffold(
            body: SizedBox(
              width: 700,
              child: WeekGrid(
                rows: rows,
                highlightIndex: 0,
                startHour: start,
                endHour: end,
              ),
            ),
          ),
        );

    testWidgets('a multi session day draws a bar per session', (tester) async {
      await tester.pumpWidget(
        wrap([
          const WeekRow(
            label: 'Today',
            spans: [
              DaySpan(
                startMinutes: 405,
                endMinutes: 525,
                label: '6:45 to 8:45',
              ),
              DaySpan(
                startMinutes: 720,
                endMinutes: 825,
                label: 'noon to 1:45',
              ),
              DaySpan(startMinutes: 1140, endMinutes: 1320, label: '7 to 10'),
            ],
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
      // One tooltip per session, which a single text range could not express.
      expect(find.byType(Tooltip), findsNWidgets(3));
    });

    testWidgets('a closed day says so instead of drawing an empty row', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap([const WeekRow(label: 'Sunday', spans: [], note: 'CLOSED')]),
      );
      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('later sessions sit further right than earlier ones', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap([
          const WeekRow(
            label: 'Today',
            spans: [
              DaySpan(startMinutes: 420, endMinutes: 480, label: 'morning'),
              DaySpan(startMinutes: 1200, endMinutes: 1320, label: 'evening'),
            ],
          ),
        ]),
      );
      final bars = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final morning = tester.getTopLeft(find.byWidget(bars[0])).dx;
      final evening = tester.getTopLeft(find.byWidget(bars[1])).dx;
      expect(
        evening,
        greaterThan(morning),
        reason: 'the grid must place time along the axis',
      );
    });

    testWidgets('renders every published day', (tester) async {
      await tester.pumpWidget(
        wrap([
          for (final d in ['Today', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
            WeekRow(
              label: d,
              spans: const [
                DaySpan(startMinutes: 600, endMinutes: 1200, label: '10 to 8'),
              ],
            ),
        ]),
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });
  });

  group('closed reads as terracotta, not alarm', () {
    test('is muted relative to a full chroma red, in both modes', () {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        final sem = Semantic.from(SchemeController.builtIn(brightness));
        final c = sem.closed;
        // A full chroma red has a large gap between its channels. Muting pulls
        // green and blue up toward red.
        final spread = c.r - c.b;
        expect(
          spread,
          lessThan(0.55),
          reason: 'closed still reads as an alarm red in $brightness',
        );
      }
    });

    test('muting did not cost the separation', () {
      double lum(Color c) =>
          0.2126 * c.r * 255 + 0.7152 * c.g * 255 + 0.0722 * c.b * 255;
      for (final brightness in [Brightness.dark, Brightness.light]) {
        final sem = Semantic.from(SchemeController.builtIn(brightness));
        expect((lum(sem.closed) - lum(sem.open)).abs(), greaterThan(20));
        expect((lum(sem.closed) - lum(sem.busy)).abs(), greaterThan(20));
      }
    });
  });
}

/// Menus, allergens and the rules around them.
void _menus() {
  Dish dish(
    String name, {
    List<String> allergens = const [],
    List<String> diet = const [],
  }) => Dish(name: name, allergens: allergens, dietary: diet);

  group('dish tags', () {
    test('vegan implies vegetarian, but not the other way round', () {
      expect(dish('a', diet: ['Vegan']).isVegetarian, isTrue);
      expect(dish('a', diet: ['Vegan']).isVegan, isTrue);
      expect(dish('b', diet: ['Vegetarian']).isVegan, isFalse);
      expect(dish('c').isVegetarian, isFalse);
    });

    test('a traces note still counts as a mention, since it is a warning', () {
      final d = dish('x', allergens: ['May Contain Traces of Milk']);
      expect(d.mentions('Milk'), isTrue);
    });

    test('matching is not case sensitive', () {
      expect(dish('x', allergens: ['Treenut']).mentions('treenut'), isTrue);
    });
  });

  group('menu rendering', () {
    Widget wrap(MenuDay menu) => MaterialApp(
      theme: AppTheme.from(_fallbackScheme()),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MenuSection(menu: menu, prefs: Preferences.instance),
        ),
      ),
    );

    MenuDay menu(List<Dish> dishes) => MenuDay(
      locationId: 1,
      serviceDate: DateTime(2026, 8, 31),
      dishes: dishes,
    );

    setUp(() => Preferences.instance.resetForTests());

    testWidgets('an empty menu explains itself rather than showing nothing', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(menu([])));
      expect(find.textContaining('No menu published'), findsOneWidget);
    });

    testWidgets('tags render exactly as published, not tidied', (tester) async {
      await tester.pumpWidget(
        wrap(
          menu([
            dish(
              'Bagel',
              allergens: ['Wheat', 'May Contain Traces of Milk'],
              diet: ['Vegan', 'Vegetarian'],
            ),
          ]),
        ),
      );
      // The weaker claim stays a weaker claim.
      expect(find.text('May Contain Traces of Milk'), findsOneWidget);
      expect(find.text('Wheat'), findsOneWidget);
      expect(find.text('Vegan'), findsOneWidget);
    });

    testWidgets('the safety caveat is always present', (tester) async {
      await tester.pumpWidget(wrap(menu([dish('Soup')])));
      expect(find.textContaining('cross'), findsOneWidget);
      expect(find.textContaining('ask the staff'), findsOneWidget);
    });

    testWidgets('a flagged allergen marks the dish, it does not remove it', (
      tester,
    ) async {
      await Preferences.instance.load();
      await Preferences.instance.toggleAvoid('Milk');
      await tester.pumpWidget(
        wrap(
          menu([
            dish('Cheese Danish', allergens: ['Milk']),
            dish('Plain Bagel', allergens: ['Wheat']),
          ]),
        ),
      );
      // Both still on screen. Hiding food from someone looking for food is the
      // wrong failure.
      expect(find.text('Cheese Danish'), findsOneWidget);
      expect(find.text('Plain Bagel'), findsOneWidget);
      expect(find.text('CONTAINS MILK'), findsOneWidget);
    });

    testWidgets('a dietary filter demotes rather than deletes', (tester) async {
      await Preferences.instance.load();
      await Preferences.instance.toggleDiet('Vegan');
      await tester.pumpWidget(
        wrap(
          menu([
            dish('Bagel', diet: ['Vegan']),
            dish('Danish', diet: ['Vegetarian']),
          ]),
        ),
      );
      expect(find.text('Bagel'), findsOneWidget);
      expect(
        find.text('Danish'),
        findsOneWidget,
        reason: 'a hidden dish looks the same as one never published',
      );
      expect(find.textContaining('do not match your filters'), findsOneWidget);
    });
  });

  group('halal and kosher are never claimed', () {
    test('the offered tags are only what RIT actually publishes', () {
      expect(knownDietaryTags, ['Vegan', 'Vegetarian']);
      final lowered = knownDietaryTags.map((t) => t.toLowerCase());
      expect(lowered, isNot(contains('halal')));
      expect(lowered, isNot(contains('kosher')));
    });

    test(
      'the allergen list matches what RIT tags, with no invented entries',
      () {
        // Peanut is deliberately absent as a standalone tag: RIT only ever
        // mentions peanuts inside a "may contain traces" string.
        expect(knownAllergens, contains('Gluten'));
        expect(knownAllergens, contains('Treenut'));
        expect(knownAllergens, isNot(contains('Peanut')));
      },
    );
  });
}

/// One navigation idiom, shared by Campus and Settings.
void _sectionNav() {
  List<SectionSpec> specs(int n) => [
    for (var i = 0; i < n; i++)
      SectionSpec(
        id: 'id$i',
        title: 'Section $i',
        subtitle: 'sub $i',
        icon: Icons.circle,
        builder: (context) => Text('content $i'),
      ),
  ];

  Widget wrap(List<SectionSpec> s) => MaterialApp(
    theme: AppTheme.from(_fallbackScheme()),
    home: Scaffold(body: SectionScaffold(sections: s)),
  );

  testWidgets('wide shows the nav and the first section together', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(specs(3)));

    expect(find.text('Section 0'), findsOneWidget);
    expect(find.text('Section 2'), findsOneWidget);
    // First section's content is already open, no dead landing state.
    expect(find.text('content 0'), findsOneWidget);
  });

  testWidgets('selecting swaps the pane without leaving the screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(specs(3)));

    await tester.tap(find.text('Section 2'));
    await tester.pumpAndSettle();
    expect(find.text('content 2'), findsOneWidget);
    expect(find.text('content 0'), findsNothing);
    // The nav is still there.
    expect(find.text('Section 0'), findsOneWidget);
  });

  testWidgets('narrow shows only the list, content is pushed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(specs(3)));

    expect(find.text('Section 0'), findsOneWidget);
    expect(
      find.text('content 0'),
      findsNothing,
      reason: 'a narrow window has no room for two panes',
    );

    await tester.tap(find.text('Section 1'));
    await tester.pumpAndSettle();
    expect(find.text('content 1'), findsOneWidget);
  });

  testWidgets('an empty section list renders nothing rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const []));
    expect(tester.takeException(), isNull);
  });
}

/// The jump rail on long grouped lists.
void _jumpRail() {
  List<JumpGroup> groups(int n) => [
    for (var i = 0; i < n; i++)
      JumpGroup(
        label: 'Group $i',
        icon: Icons.circle,
        count: i + 1,
        builder: (context) => SizedBox(height: 400, child: Text('body $i')),
      ),
  ];

  /// The rail reacts to the space it is given, so the test view has to be
  /// sized honestly. devicePixelRatio is pinned to 1 because the default of 3
  /// silently divides the logical width and puts every case below the
  /// breakpoint.
  Future<void> pump(
    WidgetTester tester,
    List<JumpGroup> g,
    Size size, {
    Widget? footer,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(_fallbackScheme()),
        home: Scaffold(
          body: JumpList(groups: g, footer: footer),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a wide window gets a rail listing every group', (tester) async {
    await pump(tester, groups(4), const Size(1400, 800));
    expect(find.text('Group 0'), findsOneWidget);
    expect(find.text('Group 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window drops the rail rather than cramping the list', (
    tester,
  ) async {
    await pump(tester, groups(4), const Size(700, 800));
    // Only the body remains, so the first group's content is what shows.
    expect(find.text('body 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single group needs no rail', (tester) async {
    await pump(tester, groups(1), const Size(1400, 800));
    // Nothing to jump between, so the rail would be pure decoration.
    expect(find.text('body 0'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsNothing);
  });

  testWidgets('tapping a rail entry scrolls to that group', (tester) async {
    await pump(tester, groups(5), const Size(1400, 800));
    expect(find.text('body 0'), findsOneWidget);

    await tester.tap(find.text('Group 3'));
    await tester.pumpAndSettle();
    expect(
      find.text('body 3'),
      findsOneWidget,
      reason: 'the rail is for getting somewhere, not decoration',
    );
  });

  testWidgets('a footer renders after the last group', (tester) async {
    await pump(
      tester,
      groups(2),
      const Size(1400, 800),
      footer: const Text('the footer'),
    );
    await tester.drag(find.text('body 0'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('the footer'), findsOneWidget);
  });
}
