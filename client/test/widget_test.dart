/// Client tests. No network: the API client is driven with a mock http client.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/freshness.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/theme/tokens.dart';
import 'package:tigerhub/widgets/bounded_list.dart';
import 'package:tigerhub/widgets/more_row.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';
import 'package:tigerhub/widgets/occupancy_chip.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('data states', () {
    test('first launch with no cache and no server is priming', () async {
      final api = ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final results = await api.dining().toList();
      expect(results.first.state, DataState.priming);
      expect(results.last.state, DataState.priming);
      expect(results.last.hasData, isFalse);
    });

    test('successful fetch is ok and caches for next launch', () async {
      final body = jsonEncode({
        'data': [
          {'id': 23, 'name': 'Crossroads', 'is_open': true, 'occupancy': null},
        ],
        'stale': false,
        'last_updated': '2026-08-28T12:00:00Z',
      });
      final api = ApiClient(client: MockClient((_) async => http.Response(body, 200)));
      final results = await api.dining().toList();
      expect(results.last.state, DataState.ok);
      expect(results.last.value!.data.single.name, 'Crossroads');

      // A second client with no network must still serve the cached payload.
      final offline = ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final replay = await offline.dining().toList();
      expect(replay.first.state, DataState.stale);
      expect(replay.first.value!.data.single.name, 'Crossroads');
      expect(replay.last.state, DataState.failing);
      expect(replay.last.hasData, isTrue, reason: 'stale cache must never become an error');
    });

    test('server reported staleness is mirrored, not recomputed', () async {
      final body = jsonEncode({'data': [], 'stale': true, 'last_updated': null});
      final api = ApiClient(client: MockClient((_) async => http.Response(body, 200)));
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
    testWidgets('over capacity says busy, not a precise percentage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(
              occupancy: Occupancy(
                count: 46, maxOcc: 38, percentFull: 100, overCapacity: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('busy'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing,
          reason: 'a wrong denominator must not be quoted as a precise figure');
    });

    testWidgets('a count with no denominator shows the count, not a ratio',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyChip(occupancy: Occupancy(count: 235, percentFull: null)),
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
          home: Scaffold(body: Center(child: SizedBox(height: height, child: child))),
        );

    testWidgets('shows only rows that fit and counts the rest', (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 12,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
      ));
      // (340 - 46) / 44 = 6 rows fit alongside the footer.
      expect(find.text('row 5'), findsOneWidget);
      expect(find.text('row 6'), findsNothing);
      expect(find.text('+6 locations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the footer is fully inside the box, never clipped',
        (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 12,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
      ));
      final box = tester.getRect(find.byType(BoundedList));
      final footer = tester.getRect(find.byType(MoreRow));
      expect(footer.bottom, lessThanOrEqualTo(box.bottom + 0.5),
          reason: 'the "+N more" row must be visible, not cut off');
    });

    testWidgets('no footer when everything fits', (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 3,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
      ));
      expect(find.byType(MoreRow), findsNothing);
      expect(find.text('row 2'), findsOneWidget);
    });

    testWidgets('a shorter box withholds more, and still says so',
        (tester) async {
      await tester.pumpWidget(boxed(
        BoundedList(
          itemCount: 12,
          itemHeight: rowHeight,
          noun: 'locations',
          itemBuilder: (context, i) => Text('row $i'),
        ),
        height: 2 * rowHeight + footerHeight,
      ));
      expect(find.text('row 1'), findsOneWidget);
      expect(find.text('row 2'), findsNothing);
      expect(find.text('+10 locations'), findsOneWidget);
    });

    testWidgets('dining shows at least 5 rows at the minimum card height',
        (tester) async {
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
      await tester.pumpWidget(boxed(
        DiningCard(
          result: Result(
            value: Collection(data: locations, stale: false),
            state: DataState.ok,
          ),
        ),
        height: 480,
      ));
      expect(tester.takeException(), isNull);
      final rows = [
        for (var i = 0; i < 24; i++)
          if (find.text('Place ${i.toString().padLeft(2, '0')}').evaluate().isNotEmpty) i,
      ];
      expect(rows.length, greaterThanOrEqualTo(5),
          reason: 'the inline hero must buy back list rows');
      expect(find.byType(MoreRow), findsOneWidget);
      // The badge is still present, just beside the title.
      expect(find.byType(ScallopedBadge), findsOneWidget);
    });

    testWidgets('dining bounds itself and keeps open locations first',
        (tester) async {
      final locations = [
        for (var i = 0; i < 12; i++)
          DiningLocation(
            id: i,
            name: 'Place ${i.toString().padLeft(2, '0')}',
            isOpen: i < 3,
          ),
      ];
      await tester.pumpWidget(boxed(
        DiningCard(
          result: Result(
            value: Collection(data: locations, stale: false),
            state: DataState.ok,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Place 00'), findsOneWidget);
      expect(find.text('Place 11'), findsNothing);
      expect(find.byType(MoreRow), findsOneWidget);
    });

    testWidgets('dining footer and visible open rows equal the hero count',
        (tester) async {
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

      await tester.pumpWidget(boxed(
        DiningCard(
          result: Result(
            value: Collection(data: locations, stale: false),
            state: DataState.ok,
          ),
        ),
        height: 700,
      ));

      final visibleOpen = find
          .byWidgetPredicate(
            (widget) => widget is Text && (widget.data?.startsWith('Open ') ?? false),
          )
          .evaluate()
          .length;
      const heroOpen = 14;
      const hiddenOpen = 5;
      expect(find.text('+$hiddenOpen open'), findsOneWidget);
      expect(visibleOpen + hiddenOpen, heroOpen);
      expect(find.textContaining('Closed '), findsNothing,
          reason: 'open locations must fill the visible rows first');
    });

    testWidgets('more row is tappable for the future detail view',
        (tester) async {
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

    testWidgets('stale data shows a quiet timestamp and no spinner', (tester) async {
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

    testWidgets('failing shows the same text with a warning icon', (tester) async {
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
      final light = schemeFromJson({
        ..._caelestiaSample,
        'mode': 'light',
      });
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
      expect(schemeFromJson({'colours': {'primary': 'f6ba96'}}), isNull);
      expect(schemeFromJson({'nope': true}), isNull);
    });

    test('container levels are derived from the tint so nesting stays visible', () {
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
    });

    test('forcing the seed yields a usable palette with no scheme file', () async {
      final controller = SchemeController(forceSeed: true);
      await controller.load();
      expect(controller.state.origin, SchemeOrigin.seed);
      expect(controller.state.isDynamic, isFalse);
      // The escape hatch must always produce something readable.
      final theme = AppTheme.from(controller.state.scheme);
      expect(theme.colorScheme.primary, isNotNull);
      controller.dispose();
    });

    test('the seed toggle flips back and forth', () async {
      final controller = SchemeController(forceSeed: true);
      await controller.load();
      expect(controller.forcedToSeed, isTrue);
      await controller.setForceSeed(false);
      expect(controller.forcedToSeed, isFalse);
      controller.dispose();
    });

    testWidgets('palette icon tooltip identifies source and action', (tester) async {
      final controller = SchemeController(forceSeed: true);
      await controller.load();
      final api = ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      await tester.pumpWidget(
        MaterialApp(home: AppShell(api: api, scheme: controller)),
      );
      await tester.pump();

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
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
      expect(badge.pointRounding + badge.valleyRounding, lessThanOrEqualTo(1.0));
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
        expect(levels[i].r, greaterThan(levels[i - 1].r),
            reason: 'each nested level must step one lighter');
      }
      for (final c in levels) {
        expect(c.r, greaterThan(c.b),
            reason: 'surfaces must be warm tinted, not neutral grey');
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

    testWidgets('the dining hero counts open locations, not one unrelated one',
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
    });

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
      expect(tall, greaterThan(short),
          reason: 'growing the card must turn into more rows');
    });

    testWidgets('the footer stays inside the box at several window sizes',
        (tester) async {
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
        expect(footer.bottom, lessThanOrEqualTo(box.bottom + 0.5),
            reason: 'footer escaped the box at height $height');
      }
    });
  });
}
