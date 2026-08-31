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

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpCampus(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1500, 1000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
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
    expect(find.textContaining('Last day of the fall'), findsOneWidget);
  });

  testWidgets('safety contacts copy the exact official number', (tester) async {
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
          (d) => d.startsWith('OPEN \u00b7 ') || d.startsWith('CLOSED \u00b7 '),
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
      expect(line, anyOf(startsWith('OPEN'), startsWith('CLOSED')));
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
      labels.any((d) => d == 'FALL' || d == 'SUMMER'),
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
    // weekdays. Captioning each half "MON TO FRI" reads as two separate rules.
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((d) => d == 'MON TO FRI')
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
