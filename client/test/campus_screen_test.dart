/// The Campus tab, driven by real captured data through the real backend path.
///
/// The gym and pool section is the reason this exists. Its projection returned
/// the wrong shape and the section rendered empty, and every other test still
/// passed: the scrape was correct, the parse matched the backend, and the model
/// parsed the malformed input without complaint into empty lists.
///
/// The only thing that would have caught it is asking the actual screen whether
/// anything appeared. So this pumps CampusScreen against a backend serving the
/// real fixtures, opens each section, and looks for content.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/data/sources/recreation.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/empty_state.dart';
import 'package:tigerhub/widgets/section_nav.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'golden_harness.dart';
import 'support/truncation.dart';

/// Serves the same envelopes LocalBackend does, from captured fixtures, with no
/// network and no clock dependence.
class _FixtureBackend implements Backend {
  _FixtureBackend(this.config);

  final StaticConfig config;

  Map<String, dynamic> _envelope(List<dynamic> data) => {
    'data': data,
    'stale': false,
    'last_updated': null,
  };

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    switch (path) {
      case '/post-offices':
        return _envelope(config.postOffices);
      case '/housing/areas':
        return _envelope(config.housingAreas);
      case '/makerspace/hours':
        return {'items': config.shedSpaces};
      case '/makerspace/rooms':
        return _envelope([
          {'room': 'Wood Shop', 'machines': 15, 'available': 12, 'in_use': 3},
        ]);
      case '/recreation/hours':
        final rows = parseRecreation(
          File('test/fixtures/recreation.html').readAsStringSync(),
          today: DateTime.utc(2026, 8, 30),
        );
        return _envelope(recreationFacilities({'rows': rows}));
      case '/campus/places':
        final kinds = <String, List<Map<String, dynamic>>>{};
        parseCampusPlaces(
          File('test/fixtures/maps_category_35.data').readAsStringSync(),
        ).forEach((subId, places) => kinds[placeKinds[subId]!.$1] = places);
        return _envelope(placeKindSummary({'kinds': kinds}));
      case '/campus/map':
        return _envelope(
          parseCampusMapFeatures(
            File('test/fixtures/maps_category_35.data').readAsStringSync(),
          ),
        );
    }
    throw UnimplementedError(path);
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StaticConfig config;

  setUpAll(() {
    final files = <String, Map<String, dynamic>>{};
    for (final name in [
      'dining_categories',
      'post_offices',
      'housing_areas',
      'shed_hours',
      'fd_locations',
    ]) {
      files[name] = jsonDecode(
        File('assets/config/$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    }
    StaticConfig.overrideForTesting(files);
    config = StaticConfig.instance;
  });

  setUpAll(() async {
    await (FontLoader(
      'GoldenRubik',
    )..addFont(rootBundle.load('assets/fonts/Rubik.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpCampus(
    WidgetTester tester, {
    Size size = const Size(1500, 1000),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    TargetPlatform? platform,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final theme = AppTheme.from(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFFF76902),
        brightness: brightness,
      ),
    ).copyWith(platform: platform);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'GoldenRubik'),
        ),
        home: Scaffold(
          body: CampusScreen(
            api: ApiClient(backend: _FixtureBackend(config)),
            now: DateTime(2026, 8, 30),
            areas: Result(
              value: Collection(
                data: config.housingAreas.map(HousingArea.fromJson).toList(),
                stale: false,
              ),
              state: DataState.ok,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the gym and pool section actually lists facilities', (
    tester,
  ) async {
    await pumpCampus(tester);

    await tester.tap(find.text('Gym and pool'));
    await tester.pumpAndSettle();

    // The captured page carries nine facilities. Naming one is the point:
    // an empty section and a working one both render without error.
    expect(
      find.textContaining('Aquatic'),
      findsWidgets,
      reason: 'the pool is missing, which is how the shape bug looked',
    );
  });

  testWidgets('Campus includes quick links', (tester) async {
    await pumpCampus(tester);
    await tester.tap(find.text('Quick links'));
    await tester.pumpAndSettle();
    for (final label in ['Tiger Spend', 'SIS', 'myCourses', 'eServices', 'Tiger Chat', 'Service Center', 'FMS requests', 'Reserve']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('find on campus lists a kind with a real label', (tester) async {
    await pumpCampus(tester);

    await tester.tap(find.text('Find on campus'));
    await tester.pumpAndSettle();

    // "Water fountains" is the kind_name. A blank here was the other shape bug.
    expect(
      find.textContaining('Water'),
      findsWidgets,
      reason: 'a place kind rendered without its label',
    );
  });

  testWidgets('academic dates surfaces the next official deadline', (
    tester,
  ) async {
    await pumpCampus(tester);

    await tester.tap(find.text('Academic dates'));
    await tester.pumpAndSettle();

    expect(find.text('Add/drop ends'), findsOneWidget);
    expect(find.text('Last day to add or drop'), findsOneWidget);
  });

  testWidgets('safety contacts dial the exact official number', (tester) async {
    final launcher = _FakeLauncher(succeeds: true);
    UrlLauncherPlatform.instance = launcher;

    await pumpCampus(tester);

    await tester.tap(find.text('Safety'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(launcher.launched, ['tel:5854753333']);
  });

  testWidgets('safety text and Service Center use their official actions', (
    tester,
  ) async {
    final launcher = _FakeLauncher(succeeds: true);
    UrlLauncherPlatform.instance = launcher;
    await pumpCampus(tester);
    await tester.tap(find.text('Safety'));
    await tester.pumpAndSettle();

    expect(find.text('Emergency text'), findsOneWidget);
    expect(find.text('585-205-8333'), findsOneWidget);
    expect(find.text('RIT Service Center'), findsOneWidget);
    expect(find.text('585-475-5000'), findsOneWidget);

    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Semantics) return false;
        final row = widget;
        return row.properties.label == 'Emergency text, 585-205-8333' &&
            row.properties.hint == 'Texts 585-205-8333';
      }),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Semantics) return false;
        final row = widget;
        return row.properties.label == 'RIT Service Center, 585-475-5000' &&
            row.properties.hint == 'Calls 585-475-5000';
      }),
      findsOneWidget,
    );

    await tester.tap(find.text('Emergency text'));
    await tester.pump();
    await tester.tap(find.text('RIT Service Center'));
    await tester.pump();
    expect(launcher.launched, ['sms:5852058333', 'tel:5854755000']);
  });

  for (final size in const [Size(390, 844), Size(430, 932)]) {
    for (final brightness in Brightness.values) {
      for (final textScale in const [1.0, 2.0]) {
        goldenWidgets(
          'campus safety${size.width.toInt()}x${size.height.toInt()} ${brightness.name} ${textScale}x',
          (tester) async {
            await pumpCampus(
              tester,
              size: size,
              brightness: brightness,
              textScale: textScale,
            );
            await tester.tap(find.text('Safety'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byType(Scaffold),
              matchesGoldenFile(
                'goldens/campus_safety_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${textScale.toInt()}x.png',
              ),
            );
          },
        );
      }
    }
  }

  // the pushed section on iOS: back chevron, call and text marks
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in Brightness.values) {
      for (final textScale in const [1.0, 2.0]) {
        final name = 'campus_safety_ios_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${textScale.toInt()}x.png';
        goldenWidgets(name, (tester) async {
          await pumpCampus(tester, size: size, brightness: brightness, textScale: textScale, platform: TargetPlatform.iOS);
          await tester.tap(find.text('Safety'));
          await tester.pumpAndSettle();
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
        });
      }
    }
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in Brightness.values) {
      for (final textScale in const [1.0, 2.0]) {
        final name = 'campus_nav_ios_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${textScale.toInt()}x.png';
        goldenWidgets(name, (tester) async {
          await pumpCampus(tester, size: size, brightness: brightness, textScale: textScale, platform: TargetPlatform.iOS);
          expect(find.text('Mail'), findsOneWidget);
          expect(find.text('Find on campus'), findsOneWidget);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
          // at 2x the last rows are below the fold
          if (textScale > 1) {
            await tester.scrollUntilVisible(find.text('SHED makerspace'), 200);
            await tester.pumpAndSettle();
            await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/${name.replaceFirst('.png', '_end.png')}'));
          }
          expect(find.text('SHED makerspace'), findsOneWidget);
        });
      }
    }
  }

  // static copy fits one line on the phones we ship to. At large text it gets
  // two; these still need a third at 2x, beside a trailing date or in a nav row
  const needThirdLineAt2x = {
    390: {
      'Fountains, restrooms, blue lights',
      'No classes October 12–13',
      'Last day to drop with a W',
      'Graduation applications due',
      'Final exams begin December 9',
      'First day of spring add/drop',
    },
    440: {
      'Graduation applications due',
      'Final exams begin December 9',
      'First day of spring add/drop',
    },
  };
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
      for (final textScale in const [1.0, 2.0]) {
        testWidgets('no row subtitle is cut short at ${size.width.toInt()} on ${platform.name} at ${textScale}x', (tester) async {
          await pumpCampus(tester, size: size, platform: platform, textScale: textScale);
          final cut = <String>{};
          final wraps = <String>{};
          final oneLine = <String>{};
          Finder vertical() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
          void collect() {
            cut.addAll(truncatedRowText(tester));
            wraps.addAll(multiLineRowText(tester));
            oneLine.addAll(singleLineRowText(tester));
          }

          // lists build lazily, so walk each one to its end
          Future<void> walk() async {
            final list = tester.state<ScrollableState>(vertical());
            while (true) {
              collect();
              final before = list.position.pixels;
              list.position.jumpTo((before + 300).clamp(0, list.position.maxScrollExtent));
              await tester.pumpAndSettle();
              if (list.position.pixels == before) break;
            }
          }

          const titles = ['Mail', 'Find on campus', 'Academic dates', 'Shuttles', 'Safety', 'Quick links', 'Gym and pool', 'SHED makerspace'];
          await walk();
          // open each section as the nav list brings it on screen
          final nav = tester.state<ScrollableState>(vertical());
          nav.position.jumpTo(0);
          await tester.pumpAndSettle();
          final visited = <String>{};
          while (true) {
            for (final title in titles) {
              final row = find.descendant(of: find.byType(SectionNavRow), matching: find.text(title)).hitTestable();
              if (visited.contains(title) || row.evaluate().isEmpty) continue;
              visited.add(title);
              await tester.tap(row);
              await tester.pumpAndSettle();
              await walk();
              await tester.pageBack();
              await tester.pumpAndSettle();
            }
            final before = nav.position.pixels;
            nav.position.jumpTo((before + 300).clamp(0, nav.position.maxScrollExtent));
            await tester.pumpAndSettle();
            if (nav.position.pixels == before) break;
          }
          expect(visited, titles.toSet(), reason: 'every section opened');
          if (textScale == 1) {
            expect(cut, isEmpty);
            expect(wraps, isEmpty, reason: 'one line at 1x');
          } else {
            expect(oneLine, isEmpty, reason: 'two lines at large text');
            expect(cut, needThirdLineAt2x[size.width.toInt()]);
          }
        });
      }
    }
  }

  // dinings food truck rows draw 18 in a 32 circle, campus fills its circles the same
  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('every campus circle holds its glyph at the dining ratio, ${platform.name}', (tester) async {
      await pumpCampus(tester, platform: platform);
      final circles = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle);
      var checked = 0;
      for (final title in const ['Mail', 'Find on campus', 'Academic dates', 'Shuttles', 'Safety', 'Quick links', 'Gym and pool', 'SHED makerspace']) {
        await tester.tap(find.descendant(of: find.byType(SectionNavRow), matching: find.text(title)));
        await tester.pumpAndSettle();
        for (final circle in circles.evaluate()) {
          final icon = find.descendant(of: find.byWidget(circle.widget), matching: find.byType(Icon));
          // the empty state mark has its own size
          if (icon.evaluate().isEmpty || find.ancestor(of: find.byWidget(circle.widget), matching: find.byType(EmptyState)).evaluate().isNotEmpty) continue;
          final outer = tester.getRect(find.byWidget(circle.widget));
          expect(tester.widget<Icon>(icon.first).size! / outer.width, closeTo(18 / 32, 0.01), reason: '$title circle');
          final glyph = tester.getRect(find.descendant(of: icon.first, matching: find.byType(RichText)));
          expect(outer.contains(glyph.topLeft) && outer.contains(glyph.bottomRight - const Offset(0.001, 0.001)), isTrue, reason: '$title glyph $glyph outside $outer');
          checked++;
        }
      }
      expect(checked, greaterThan(20));
    });
  }

  testWidgets('with no dialer the number is copied instead', (tester) async {
    UrlLauncherPlatform.instance = _FakeLauncher(succeeds: false);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpCampus(tester);

    await tester.tap(find.text('Safety'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, '585-475-3333');
  });

  testWidgets('shuttles uses the saved home and today’s schedule', (
    tester,
  ) async {
    await Preferences.instance.setHome(area: 'global-village');
    await pumpCampus(tester);

    await tester.tap(find.text('Shuttles'));
    await tester.pumpAndSettle();

    expect(find.text('Today from Global Village'), findsOneWidget);
    // August 30, 2026 is Sunday, so weekday Campus Connection routes must not
    // be mixed into the useful answer for today.
    expect(find.textContaining('13 · Campus & Inn'), findsOneWidget);
    expect(find.textContaining('3 · Campus Connection'), findsNothing);
  });

  testWidgets('the map is no longer buried inside Campus', (tester) async {
    // It moved to its own tab, so Campus must not carry a second copy: two
    // screens subscribing to the same feed for the same pixels is waste, and
    // the duplicate is the one that goes stale.
    await pumpCampus(tester);
    expect(find.text('Campus map'), findsNothing);
  });

  testWidgets('mail shows a real post office address', (tester) async {
    await pumpCampus(tester);

    // RIT's mail is zone based, so these two offices are the whole answer.
    expect(find.textContaining('Global Village Post Office'), findsWidgets);
    expect(find.textContaining('6000 Reynolds Drive'), findsWidgets);
  });

  testWidgets('each post office service says what it is doing now', (
    tester,
  ) async {
    // The week's table is for planning. This line is for standing outside
    // deciding whether to walk over.
    await pumpCampus(tester);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();

    final statusLines = labels
        .where(
          (d) => d.startsWith('Open \u00b7 ') || d.startsWith('Closed \u00b7 '),
        )
        .toList();

    expect(
      statusLines,
      isNotEmpty,
      reason: 'no service reported its state for today',
    );

    // Two offices, each running package pickup and a shipping window.
    expect(statusLines.length, greaterThanOrEqualTo(2));

    // Status is stated in words, never by the dot alone.
    for (final line in statusLines) {
      expect(line, anyOf(startsWith('Open'), startsWith('Closed')));
    }
  });

  testWidgets('each service states its season', (tester) async {
    // RIT publishes fall and summer separately, and the difference is easy to
    // be caught out by, so the module says which one it is showing.
    await pumpCampus(tester);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toSet();

    expect(
      labels.any((d) => d == 'Fall' || d == 'Summer'),
      isTrue,
      reason: 'the hours shown belong to a season that is never named',
    );
  });

  testWidgets('pickup and shipping are never merged', (tester) async {
    // They can run different seasons, days and hours. Combining them would
    // invent a schedule neither of them has.
    await pumpCampus(tester);
    expect(find.text('Package pickup'), findsWidgets);
    expect(find.text('Shipping window'), findsWidgets);
  });

  testWidgets('a split shift is captioned once, not twice', (tester) async {
    await pumpCampus(tester);

    // The shipping window closes over lunch, arriving as two rules on the same
    // weekdays. Captioning each half "Mon to Fri" reads as two separate rules.
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((d) => d == 'Mon to Fri')
        .length;

    expect(labels, greaterThan(0), reason: 'no weekday hours rendered at all');

    final times = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((d) => d.contains(' to ') && RegExp(r'\d').hasMatch(d))
        .length;

    expect(
      times,
      greaterThan(labels),
      reason:
          'every time got its own caption, so the split shift reads as '
          'two rules rather than one lunch closure',
    );
  });
}

class _FakeLauncher extends MethodChannelUrlLauncher
    with MockPlatformInterfaceMixin {
  _FakeLauncher({required this.succeeds});

  final bool succeeds;
  final launched = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (succeeds) launched.add(url);
    return succeeds;
  }
}
