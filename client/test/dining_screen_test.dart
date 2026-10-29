import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/chef_location_color.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/inset_group.dart';
import 'package:tigerhub/widgets/segmented_picker.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

class _DiningBackend implements Backend {
  _DiningBackend(
    this.features, {
    this.chefs,
    this.dishes = const [],
  });

  // answered on /dining/specials, which the tab no longer reads
  final List<Map<String, dynamic>> features;

  // the chefs route answer, or a failed read when null
  final Map<String, dynamic>? chefs;

  // the dishes on place 23's menu
  final List<Map<String, dynamic>> dishes;

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (path == '/dining/specials') {
      return {'data': features, 'stale': false, 'last_updated': null};
    }
    if (path == '/dining/visiting-chefs' && chefs != null) return chefs!;
    if (path == '/dining/23/menu') {
      return {'service_date': '2026-10-14', 'location_id': 23, 'dishes': dishes, 'stale': false, 'last_updated': null};
    }
    throw UnimplementedError(path);
  }

  @override
  void close() {}
}

Map<String, dynamic> _chef(int id, String name, {String? cuisine, String? place}) => {
  'id': id,
  'name': name,
  'cuisine': cuisine,
  'location_name': place ?? '',
  'start_time': '2026-10-14T15:00:00Z',
  'end_time': '2026-10-14T18:00:00Z',
};

Map<String, dynamic> _chefsBody(
  List<Map<String, dynamic>> data, {
  String availability = 'available',
  Map<String, dynamic>? next,
}) => {
  'data': data,
  'stale': false,
  'last_updated': null,
  'availability': availability,
  'next': ?next,
};

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // pinned to Wed Oct 14 2026 noon, the day the chef times are on
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });
  tearDown(RitClock.reset);
  // the cache singleton keeps its first store, so empty it between tests
  setUp(() => ResponseCache.instance.prune(olderThan: const Duration(days: -1)));

  Future<void> pumpDining(
    WidgetTester tester,
    List<Map<String, dynamic>> features, {
    Size size = const Size(1000, 900),
    _DiningBackend? backend,
    Brightness brightness = Brightness.light,
    double scale = 1,
    List<DiningLocation>? places,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.from(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFFF76902),
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: DiningScreen(
            api: ApiClient(backend: backend ?? _DiningBackend(features)),
            result: Result(
              value: Collection(
                data: places ?? const [
                  DiningLocation(
                    id: 23,
                    name: 'Crossroads',
                    category: 'food-court',
                    categoryName: 'Food courts',
                    isOpen: true,
                  ),
                  DiningLocation(
                    id: 24,
                    name: 'Midnight Oil',
                    category: 'coffee',
                    categoryName: 'Coffee',
                    isOpen: false,
                  ),
                ],
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

  group('visiting chefs group', () {
    final chefs = _chefsBody([
      _chef(1, 'Chef Marco', cuisine: 'Italian', place: 'Crossroads'),
      _chef(2, 'Chef Lin', cuisine: 'Sichuan', place: 'Gracie’s'),
    ]);

    for (final width in [390.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('shows each time and location whole at $width, ${scale}x', (tester) async {
          final body = _chefsBody([
            _chef(1, 'Chef Marco', place: 'The Cafe & Market at Crossroads'),
            _chef(2, 'Chef Lin', place: 'Kitchen at Brick City'),
          ]);
          await pumpDining(
            tester,
            const [],
            size: Size(width, 844),
            scale: scale,
            backend: _DiningBackend(const [], chefs: body),
          );
          for (final text in ['The Cafe & Market at Crossroads', 'Kitchen at Brick City']) {
            expect(find.text(text), findsOneWidget, reason: text);
            final paragraph = find.descendant(of: find.text(text), matching: find.byType(RichText));
            expect(tester.renderObject<RenderParagraph>(paragraph.first).didExceedMaxLines, isFalse);
          }
          expect(find.text('11 AM to 2 PM'), findsNWidgets(2));
        });
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('colours the location by id, ${brightness.name}', (tester) async {
        await pumpDining(
          tester,
          const [],
          brightness: brightness,
          backend: _DiningBackend(const [], chefs: chefs),
        );
        Color? colourOf(String chef) {
          final row = find.byKey(ValueKey('chef-$chef'));
          final place = chef == '1' ? 'Crossroads' : 'Gracie’s';
          return tester.widget<Text>(find.descendant(of: row, matching: find.text(place))).style?.color;
        }
        final dark = brightness == Brightness.dark;
        // no ids in this feed, so the names resolve: Crossroads is 23, Gracie's 21
        expect(colourOf('1'), dark ? chefLocationColors[23]!.dark : chefLocationColors[23]!.light);
        expect(colourOf('2'), dark ? chefLocationColors[21]!.dark : chefLocationColors[21]!.light);
      });
    }

    group('a chef who is not on', () {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902));

      Color? nameColour(WidgetTester tester, String chef) =>
          tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('chef-$chef')), matching: find.text(chef == '1' ? 'Chef Marco' : 'Chef Lin'))).style?.color;

      Color? placeColour(WidgetTester tester, String chef) {
        final place = chef == '1' ? 'Crossroads' : 'Gracie’s';
        return tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('chef-$chef')), matching: find.text(place))).style?.color;
      }

      String label(WidgetTester tester, String chef) => tester.getSemantics(find.text(chef == '1' ? 'Chef Marco' : 'Chef Lin')).label;

      testWidgets('is muted before the slot starts, and says when', (tester) async {
        // 10 AM on campus, the slot is 11 AM to 2 PM
        RitClock.pin(DateTime.utc(2026, 10, 14, 14));
        final handle = tester.ensureSemantics();
        await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
        expect(nameColour(tester, '1'), scheme.onSurfaceVariant);
        expect(
          placeColour(tester, '1'),
          chefLocationColor(MenuItem(id: 1, name: 'Chef Marco', locationName: 'Crossroads'), scheme, muted: true),
        );
        expect(label(tester, '1'), contains('starts at 11 AM'));
        handle.dispose();
      });

      testWidgets('is muted after the slot ends while still listed, and says so', (tester) async {
        // 2:10 PM on campus
        RitClock.pin(DateTime.utc(2026, 10, 14, 18, 10));
        final handle = tester.ensureSemantics();
        await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
        expect(nameColour(tester, '2'), scheme.onSurfaceVariant);
        expect(label(tester, '2'), contains('ended'));
        handle.dispose();
      });

      testWidgets('is full strength while the slot runs', (tester) async {
        await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
        expect(nameColour(tester, '1'), isNot(scheme.onSurfaceVariant));
        expect(placeColour(tester, '1'), chefLocationColors[23]!.light);
        expect(label(tester, '1'), isNot(contains('ended')));
        expect(label(tester, '1'), isNot(contains('starts')));
      });

      testWidgets('turns full strength when the slot starts, with no data refresh', (tester) async {
        RitClock.pin(DateTime.utc(2026, 10, 14, 14, 59, 30));
        await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
        expect(nameColour(tester, '1'), scheme.onSurfaceVariant);
        RitClock.pin(DateTime.utc(2026, 10, 14, 15));
        await tester.pump(const Duration(seconds: 30));
        expect(nameColour(tester, '1'), isNot(scheme.onSurfaceVariant));
      });
    });

    testWidgets('lists each chef with time and location above the places', (tester) async {
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));

      expect(find.text('Visiting chefs'), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is GroupHeader && w.title == 'Visiting chefs'),
        findsNothing,
        reason: 'plain header, no filled bar',
      );
      expect(find.text('Chef Marco'), findsOneWidget);
      expect(find.text('11 AM to 2 PM'), findsNWidgets(2));
      // the places list below also names Crossroads, so look inside the row
      final marco = find.byKey(const ValueKey('chef-1'));
      final marcoPlace = find.descendant(of: marco, matching: find.text('Crossroads'));
      expect(marcoPlace, findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('chef-2')), matching: find.text('Gracie’s')), findsOneWidget);
      // the cuisine is a data field the icon uses, never text on the row
      expect(find.text('Italian'), findsNothing);
      expect(find.text('Sichuan'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Chef Marco')).dy,
        lessThan(tester.getTopLeft(marcoPlace).dy),
      );
    });

    testWidgets('drops a chef 30 minutes after the slot ends', (tester) async {
      RitClock.pin(DateTime.utc(2026, 10, 14, 18, 29, 59));
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
      expect(find.text('Chef Marco'), findsOneWidget);
    });

    testWidgets('keeps the group once every chef has ended, with the next chef', (tester) async {
      RitClock.pin(DateTime.utc(2026, 10, 14, 18, 30));
      final next = {'date': '2026-10-15', 'name': 'Chef Lin', 'location_name': 'Gracie’s'};
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: _chefsBody(chefs['data'] as List<Map<String, dynamic>>, next: next)));
      expect(find.text('Chef Marco'), findsNothing);
      expect(find.text('Visiting chefs'), findsWidgets);
      expect(find.text('No more chefs today'), findsOneWidget);
      expect(find.text('Next: Tomorrow · Chef Lin · Gracie’s'), findsOneWidget);
    });

    testWidgets('an ended day with no next chef still says no more chefs', (tester) async {
      RitClock.pin(DateTime.utc(2026, 10, 14, 18, 30));
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));
      expect(find.text('No more chefs today'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });

    testWidgets('rows are labelled and at least 48pt tall', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: chefs));

      final row = find.byKey(const ValueKey('chef-1'));
      expect(
        tester.getSemantics(find.descendant(of: row, matching: find.byType(Semantics)).first).label,
        startsWith('Chef Marco, 11 AM to 2 PM, Crossroads'),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    final hidden = <String, _DiningBackend>{
      'no chefs': _DiningBackend(const [], chefs: _chefsBody(const [])),
      'unavailable': _DiningBackend(const [], chefs: _chefsBody(const [], availability: 'unavailable')),
      'unavailable with rows': _DiningBackend(
        const [],
        chefs: _chefsBody([_chef(1, 'Chef Marco')], availability: 'unavailable'),
      ),
      'a failed read': _DiningBackend(const []),
    };
    for (final entry in hidden.entries) {
      testWidgets('is absent for ${entry.key}, with no warning', (tester) async {
        await pumpDining(tester, const [], backend: entry.value);

        expect(find.text('Visiting chefs'), findsNothing);
        expect(find.text('Chef Marco'), findsNothing);
        expect(find.textContaining('chefs'), findsNothing);
        expect(find.text('Crossroads'), findsOneWidget);
      });
    }

    testWidgets('a cached answer stays when the refresh fails', (tester) async {
      await ResponseCache.instance.write('/dining/visiting-chefs', chefs);
      await pumpDining(tester, const [], backend: _DiningBackend(const []));

      expect(find.text('Chef Marco'), findsOneWidget);
      expect(find.textContaining('Couldn’t'), findsNothing);
    });

  });

  // dish menus live only on a location's detail page
  testWidgets('the Dining tab lists no menu, even with published dishes', (tester) async {
    await pumpDining(tester, const [
      {'id': 42, 'name': 'Tomato bisque', 'category': 'Soup', 'location_name': 'Crossroads'},
    ]);

    expect(find.text('Today’s published menu'), findsNothing);
    expect(find.text('Tomato bisque'), findsNothing);
    expect(find.text('Soup · Crossroads'), findsNothing);
    expect(find.text('Crossroads'), findsOneWidget);
  });

  testWidgets('a location’s detail page still shows its menu', (tester) async {
    final backend = _DiningBackend(const [], dishes: const [
      {'name': 'Tomato bisque', 'category': 'Soup'},
    ]);
    await pumpDining(tester, const [], backend: backend);

    await tester.tap(find.text('Crossroads'));
    await tester.pumpAndSettle();

    expect(find.text('Tomato bisque'), findsOneWidget);
  });

  testWidgets('the default view is Open now, All adds the closed places, Favorites is empty', (tester) async {
    await pumpDining(tester, const []);

    expect(tester.widget<SegmentedPicker<DiningView>>(find.byType(SegmentedPicker<DiningView>)).value, DiningView.openNow);
    expect(find.text('Crossroads'), findsOneWidget);
    expect(find.text('Midnight Oil'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Midnight Oil'), findsOneWidget);

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('No favorites'), findsOneWidget);
    expect(find.text('Crossroads'), findsNothing);
  });

  testWidgets('with nothing open the default view is All', (tester) async {
    await pumpDining(tester, const [], places: [const DiningLocation(id: 24, name: 'Midnight Oil', isOpen: false)]);
    expect(tester.widget<SegmentedPicker<DiningView>>(find.byType(SegmentedPicker<DiningView>)).value, DiningView.all);
    expect(find.text('Midnight Oil'), findsOneWidget);
  });

  testWidgets('the type filter narrows to one venue type and clears', (tester) async {
    await pumpDining(tester, const []);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Dining hall'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('Midnight Oil'), findsOneWidget);
    expect(find.text('Crossroads'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('Crossroads'), findsOneWidget);
  });

  testWidgets('search filters locations, not dishes', (tester) async {
    await pumpDining(tester, [
      {
        'id': 42,
        'name': 'Tomato bisque',
        'category': 'Soup',
        'location_name': 'Crossroads',
      },
    ]);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search dining'),
      'tomato',
    );
    await tester.pumpAndSettle();

    expect(find.text('Tomato bisque'), findsNothing);
    expect(find.text('Crossroads'), findsNothing);
    expect(find.text('No matching locations'), findsOneWidget);
  });

  for (final scale in const [1.0, 2.0]) {
    for (final size in const [Size(390, 844), Size(440, 956)]) {
      testWidgets('the first place shows within one screen at ${size.width.toInt()} wide, text ${scale}x', (tester) async {
        await pumpDining(tester, const [], size: size, scale: scale);

        final first = tester.getRect(find.byType(StatusRow).first);
        expect(first.bottom, lessThan(size.height));
        // control and list share the content edge
        expect(tester.getRect(find.byType(SegmentedPicker<DiningView>)).left, first.left);
        expect(find.text('Order online'), findsNothing);
      });
    }
  }

  testWidgets('sections have plain titles and rows sit in inset groups', (tester) async {
    await pumpDining(tester, const [], backend: _DiningBackend(const [], chefs: _chefsBody([_chef(1, 'Chef Marco', place: 'Crossroads')])));

    expect(find.byType(GroupHeader), findsNothing);
    expect(find.byType(InsetGroup), findsWidgets);
    final group = tester.getRect(find.byType(InsetGroup).last);
    final row = tester.getRect(find.byType(StatusRow).last);
    expect(row.left, group.left);
    expect(row.right, group.right);
  });

  testWidgets('the toolbar fits a 360 wide phone', (tester) async {
    await pumpDining(tester, const [], size: const Size(360, 700));

    expect(tester.takeException(), isNull);
    for (final view in DiningView.values) {
      expect(find.text(view.label), findsOneWidget);
    }
  });

  testWidgets('control F focuses and selects the dining search', (
    tester,
  ) async {
    await pumpDining(tester, const []);
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.tapAt(const Offset(900, 800));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(
      field.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
  });

  final goldenChefs = _chefsBody([
    _chef(1, 'Chef Marco', cuisine: 'Italian', place: 'Crossroads'),
    _chef(2, 'Chef Lin', cuisine: 'Sichuan', place: 'Gracie’s'),
    _chef(3, 'Chef Amara Okonkwo-Reyes', cuisine: 'West African', place: 'Global Village Plaza'),
  ]);
  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 2.0]) {
        final name = 'dining_chefs_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x';
        goldenWidgets(name, (tester) async {
          await pumpDining(
            tester,
            const [],
            size: size,
            brightness: brightness,
            scale: scale,
            backend: _DiningBackend(const [], chefs: goldenChefs),
          );
          expect(find.text('Chef Marco'), findsOneWidget);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name.png'));
        });
      }
    }
  }
}
