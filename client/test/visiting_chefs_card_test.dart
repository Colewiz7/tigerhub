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
import 'package:tigerhub/cards/visiting_chefs_card.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/scalloped_badge.dart';

final DateTime _checked = DateTime.now().subtract(const Duration(minutes: 5));

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
  double height = 560,
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
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: RepaintBoundary(
            key: const ValueKey('card'),
            child: SizedBox(
              // The shortest a standard home card gets (homeMinCardHeight).
              height: height,
              child: VisitingChefsCard(result: result),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `flutter test` draws every font as the blocky Ahem face unless told
/// otherwise, which makes a golden useless for judging wrapping and clipping.
/// Rubik and the Material icon font are loaded so the images look like the app.
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }

  await load('Rubik', 'assets/fonts/Rubik.ttf');
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    await load(
      'MaterialIcons',
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => RitClock.pin(DateTime.utc(2026, 10, 14, 16)));
  tearDown(RitClock.reset);

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
      expect(find.text('11 AM to 2 PM'), findsOneWidget);
      expect(find.text('4 PM to 7 PM'), findsOneWidget);
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

    testWidgets('a quiet day with an upcoming chef adds one Next line', (
      tester,
    ) async {
      await pumpState(tester, 'next');
      expect(find.text('No visiting chefs today'), findsOneWidget);
      expect(
        find.text(
          'Next: Fri · Tandoor of India at The Cafe & Market at Crossroads',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tomorrow reads as Tomorrow', (tester) async {
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
      expect(find.text('Next: Tomorrow · KO-BQ at RITZ'), findsOneWidget);
    });

    testWidgets('the time and location are shown whole, not ellipsised', (
      tester,
    ) async {
      await pumpState(tester, 'available');
      for (final scale in [1.0, 2.0]) {
        await _pump(
          tester,
          result: _states['available']!,
          size: const Size(390, 844),
          brightness: Brightness.light,
          scale: scale,
        );
        for (final text in ['11 AM to 2 PM', 'The Cafe & Market at Crossroads']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(text),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: '$text at $scale');
        }
      }
    });

    testWidgets('the badge caption is one word', (tester) async {
      await pumpState(tester, 'available');
      expect(find.text('CHEFS'), findsOneWidget);
      expect(find.text('CHEFS TODAY'), findsNothing);
    });

    testWidgets('at large text the count moves out of the header', (
      tester,
    ) async {
      await _pump(
        tester,
        result: _states['available']!,
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 2,
      );
      expect(find.byType(ScallopedBadge), findsNothing);
      expect(find.text('3 chefs today'), findsOneWidget);
    });

    testWidgets('chefs that do not fit are counted as "+N more"', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < 6; i++)
          MenuItem(id: i, name: 'Chef $i', locationName: 'RITZ'),
      ];
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
      expect(find.textContaining(RegExp(r'^\+\d+ more$')), findsOneWidget);
      expect(find.textContaining('chefs'), findsOneWidget,
          reason: 'only the "6 chefs today" line, never "+N chefs"');

      await _pump(
        tester,
        result: Result(
          value: ChefCollection(data: many.take(3).toList(), stale: false),
          state: DataState.ok,
        ),
        size: const Size(390, 844),
        brightness: Brightness.light,
        scale: 2,
        height: 520,
      );
      expect(find.text('+1 chefs'), findsNothing);
    });

    testWidgets('a first run outage says Never updated, not just now', (
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
      expect(find.text('Never updated'), findsOneWidget);
      expect(find.textContaining('just now'), findsNothing);
    });

    testWidgets('unavailable is not the empty state', (tester) async {
      await pumpState(tester, 'unavailable');
      expect(find.text('Menus unavailable'), findsOneWidget);
      expect(find.text('No visiting chefs today'), findsNothing);
      expect(find.text('Updated 5m ago'), findsOneWidget);
      expect(find.text('RIT dining menus'), findsOneWidget);
    });
  });

  // A compact home card is 58% of the standard height. Flutter fails any test
  // that draws an overflow stripe, so pumping is the assertion.
  for (final scale in [1.0, 2.0]) {
    for (final state in _states.keys) {
      testWidgets('$state fits a compact card at ${scale}x', (tester) async {
        await _pump(
          tester,
          result: _states[state]!,
          size: const Size(390, 844),
          brightness: Brightness.dark,
          scale: scale,
          height: 325,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

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
          testWidgets('golden $name', skip: !Platform.isLinux, (tester) async {
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
