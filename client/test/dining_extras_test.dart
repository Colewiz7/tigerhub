/// Dining food trucks group and the two header link-outs.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/sources/food_trucks.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/data/store.dart';
import 'package:tigerhub/data/upstream.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/widgets/link_button.dart';
import 'package:tigerhub/widgets/status_row.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'golden_harness.dart';

class _Launcher extends MethodChannelUrlLauncher with MockPlatformInterfaceMixin {
  _Launcher({this.succeeds = true});

  final bool succeeds;
  final opened = <String>[];
  final modes = <PreferredLaunchMode>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    modes.add(options.mode);
    return succeeds;
  }
}

/// Serves the trucks route from [trucks], or fails it when [trucks] is null.
class _Backend implements Backend {
  const _Backend(this.trucks);

  final Map<String, dynamic>? trucks;

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async {
    if (path == '/dining/specials') return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
    if (path == '/dining/food-trucks' && trucks != null) return trucks!;
    throw UnimplementedError(path);
  }

  @override
  void close() {}
}

Map<String, dynamic> _truck(String name, String date, {String? time, String? place}) => {
  'name': name,
  'date': date,
  'time_text': time,
  'location': place,
};

Map<String, dynamic> _body(
  List<Map<String, dynamic>> data, {
  String availability = 'available',
  Duration age = Duration.zero,
}) => {
  'data': data,
  'stale': false,
  'last_updated': CampusTime.format(DateTime.now().subtract(age).toUtc()),
  'availability': availability,
};

// answers change between reads, optionally held at a gate
class _Live implements Backend {
  _Live(this.answer);

  Map<String, dynamic> Function() answer;
  Completer<void>? gate;
  var reads = 0;

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async {
    if (path == '/dining/specials') return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
    reads++;
    await gate?.future;
    return answer();
  }

  @override
  void close() {}
}

// holds the answer until release
class _Slow implements Backend {
  _Slow(this.answer);

  final Map<String, dynamic> answer;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async {
    if (path == '/dining/specials') return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
    await _gate.future;
    return answer;
  }

  @override
  void close() {}
}

// pinned to Wed Oct 14 2026, in season
final _today = DateTime.utc(2026, 10, 14, 16);

final _six = [
  _truck('Taco Loco', '2026-10-14', time: '11 a.m. to 2 p.m.', place: 'Global Village Plaza'),
  _truck('Pierogi Pals', '2026-10-15', time: '11 a.m. to 2 p.m.', place: 'Lot G'),
  _truck('Smokestack BBQ', '2026-10-16', time: '5 p.m. to 8 p.m.', place: 'Gracie’s lawn'),
  _truck('Bao Down', '2026-10-17', time: '11 a.m. to 2 p.m.', place: 'Lot G'),
  _truck('Waffle Wagon', '2026-10-20', time: '11 a.m. to 2 p.m.', place: 'Lot G'),
  _truck('Curry Up', '2026-10-21', time: '11 a.m. to 2 p.m.', place: 'Lot G'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Launcher launcher;
  late UrlLauncherPlatform previousLauncher;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    RitClock.pin(_today);
    previousLauncher = UrlLauncherPlatform.instance;
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    RitClock.reset();
    UrlLauncherPlatform.instance = previousLauncher;
  });

  Future<void> pumpDining(
    WidgetTester tester,
    Map<String, dynamic>? trucks, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
    double scale = 1,
    Future<void> Function()? seedCache,
    Backend? backend,
    ValueNotifier<int>? tick,
    ValueNotifier<bool>? tabActive,
  }) async {
    await seedCache?.call();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: brightness);
    final api = ApiClient(backend: backend ?? _Backend(trucks));
    // a new result object each build stands in for the shell's tick
    Result<Collection<DiningLocation>> diningResult() => Result(
      value: Collection(
        data: const [
          DiningLocation(
            id: 23,
            name: 'Crossroads',
            category: 'food-court',
            categoryName: 'Food courts',
            isOpen: true,
          ),
        ],
        stale: false,
      ),
      state: DataState.ok,
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.from(scheme),
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([?tick, ?tabActive]),
              builder: (context, _) => TickerMode(
                enabled: tabActive?.value ?? true,
                child: DiningScreen(api: api, result: diningResult()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('food trucks group', () {
    testWidgets('shows name, day, time and place for trucks', (tester) async {
      await pumpDining(tester, _body(_six));

      expect(find.text('Food trucks'), findsWidgets);
      expect(find.text('Taco Loco'), findsOneWidget);
      expect(find.text('Today · 11 a.m. to 2 p.m. · Global Village Plaza'), findsOneWidget);
      expect(find.text('Tomorrow · 11 a.m. to 2 p.m. · Lot G'), findsOneWidget);
      expect(find.text('Fri, Oct 16 · 5 p.m. to 8 p.m. · Gracie’s lawn'), findsOneWidget);
    });

    testWidgets('lists every truck, with no footer for the rest', (tester) async {
      final seven = [..._six, _truck('Rolling Rice', '2026-10-22', time: '5 p.m. to 8 p.m.', place: 'Lot G')];
      await pumpDining(tester, _body(seven), size: const Size(390, 3200));

      for (final name in ['Taco Loco', 'Bao Down', 'Waffle Wagon', 'Curry Up', 'Rolling Rice']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.textContaining('more'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
      final rows = find.byWidgetPredicate((w) => w is StatusRow && '${w.key}'.contains('truck-'));
      expect(rows, findsNWidgets(7));
    });

    testWidgets('a cache inside grace shows when the refresh fails', (tester) async {
      await pumpDining(
        tester,
        null,
        seedCache: () => ResponseCache.instance.write('/dining/food-trucks', _body(_six, age: const Duration(hours: 10))),
      );

      expect(find.text('Taco Loco'), findsOneWidget);
    });

    testWidgets('a cache beyond grace stays hidden when the refresh fails', (tester) async {
      await pumpDining(
        tester,
        null,
        seedCache: () => ResponseCache.instance.write('/dining/food-trucks', _body(_six, age: const Duration(hours: 20))),
      );

      expect(find.text('Food trucks'), findsNothing);
      expect(find.text('Taco Loco'), findsNothing);
      expect(find.text('Crossroads'), findsOneWidget);
    });

    testWidgets('a cache inside grace paints on the first frame and nothing moves after', (tester) async {
      final slow = _Slow(_body(_six));
      await pumpDining(
        tester,
        null,
        backend: slow,
        seedCache: () => ResponseCache.instance.write('/dining/food-trucks', _body(_six, age: const Duration(hours: 10))),
      );

      expect(find.text('Taco Loco'), findsOneWidget);
      final before = tester.getTopLeft(find.text('Crossroads'));

      slow.release();
      await tester.pumpAndSettle();

      expect(find.text('Taco Loco'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Crossroads')), before);
    });

    testWidgets('a fresh unavailable answer hides a cached available one', (tester) async {
      await pumpDining(
        tester,
        _body(const [], availability: 'unavailable'),
        seedCache: () => ResponseCache.instance.write('/dining/food-trucks', _body(_six)),
      );

      expect(find.text('Food trucks'), findsNothing);
      expect(find.text('Taco Loco'), findsNothing);
    });

    testWidgets('a fresh successful read shows the group over an old cache', (tester) async {
      await pumpDining(
        tester,
        _body([_six.first]),
        seedCache: () => ResponseCache.instance.write('/dining/food-trucks', _body(_six)),
      );

      expect(find.text('Taco Loco'), findsOneWidget);
      expect(find.text('Pierogi Pals'), findsNothing);
    });

    testWidgets('an answer older than grace hides the group', (tester) async {
      await pumpDining(tester, _body(_six, age: const Duration(hours: 20)));

      expect(find.text('Food trucks'), findsNothing);
    });

    testWidgets('a time or place that is missing is left out, not blanked', (tester) async {
      await pumpDining(tester, _body([_truck('Food Truck Rodeo', '2026-10-16')]));

      expect(find.text('Fri, Oct 16'), findsOneWidget);
    });

    final hidden = <String, Map<String, dynamic>?>{
      'no trucks': _body(const []),
      'unavailable': _body(const [], availability: 'unavailable'),
      'unavailable even with rows': _body(_six, availability: 'unavailable'),
      'empty availability': _body(_six, availability: 'empty'),
      'read failed': null,
    };
    for (final entry in hidden.entries) {
      testWidgets('is absent for ${entry.key}', (tester) async {
        await pumpDining(tester, entry.value);

        expect(find.text('Food trucks'), findsNothing);
        expect(find.text('Taco Loco'), findsNothing);
        expect(find.textContaining('No food trucks'), findsNothing);
        expect(find.text('Crossroads'), findsOneWidget);
      });
    }
  });

  group('food trucks route', () {
    late Directory dir;
    late JsonStore store;
    late LocalBackend backend;

    Map<String, dynamic> snapshot({
      String origin = 'html',
      List<Map<String, dynamic>>? trucks,
    }) => {
      'trucks': trucks ?? _six,
      'roster': <Map<String, dynamic>>[],
      'season_months': defaultFoodTruckSeasonMonths.toList()..sort(),
      'origin': origin,
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
    };

    setUp(() {
      StaticConfig.overrideForTesting({});
      dir = Directory.systemTemp.createTempSync('dining-extras');
      store = JsonStore.overrideForTesting(dir);
      backend = LocalBackend(
        upstream: Upstream(
          client: MockClient((_) async => throw const SocketException('offline')),
          maxRetries: 1,
        ),
        store: store,
      );
    });

    tearDown(() {
      backend.close();
      dir.deleteSync(recursive: true);
    });

    test('serves upcoming trucks in season', () async {
      await store.write(foodTrucksSource, snapshot());
      final body = await backend.fetch('/dining/food-trucks');

      expect(body['availability'], 'available');
      expect(body['data'], hasLength(6));
    });

    // clocks move together so the pacer lets the failing scrape run
    var attempts = 0;
    Future<Map<String, dynamic>> readAfter(Duration age) async {
      await store.write(foodTrucksSource, snapshot());
      DateTime later() => DateTime.now().add(age);
      foodTruckPacer.reset();
      foodTruckPacer.useClock(later);
      addTearDown(() {
        foodTruckPacer.useClock(null);
        foodTruckPacer.reset();
      });
      attempts = 0;
      final backend = LocalBackend(
        upstream: Upstream(
          client: MockClient((_) async {
            attempts++;
            throw const SocketException('offline');
          }),
          maxRetries: 1,
        ),
        store: store,
        clock: later,
      );
      addTearDown(backend.close);
      final body = await backend.fetch('/dining/food-trucks');
      for (var i = 0; i < 50 && attempts == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return body;
    }

    test('is unavailable with no rows when the snapshot is beyond grace and the scrape fails', () async {
      final body = await readAfter(const Duration(hours: 20));

      expect(attempts, greaterThan(0));
      expect(body['stale'], isTrue);
      expect(body['availability'], 'unavailable');
      expect(body['data'], isEmpty);
    });

    test('keeps the last trucks inside grace when the scrape fails', () async {
      final body = await readAfter(const Duration(hours: 10));

      expect(attempts, greaterThan(0));
      expect(body['stale'], isFalse);
      expect(body['availability'], 'available');
      expect(body['data'], hasLength(6));
    });

    test('is unavailable with no rows off season', () async {
      RitClock.pin(DateTime.utc(2027, 1, 20, 16));
      await store.write(
        foodTrucksSource,
        snapshot(trucks: [_truck('Taco Loco', '2027-01-21')]),
      );
      final body = await backend.fetch('/dining/food-trucks');

      expect(body['availability'], 'unavailable');
      expect(body['data'], isEmpty);
    });

    test('is unavailable when the read found nothing', () async {
      await store.write(foodTrucksSource, snapshot(origin: 'none', trucks: const []));
      final body = await backend.fetch('/dining/food-trucks');

      expect(body['availability'], 'unavailable');
      expect(body['data'], isEmpty);
    });

    test('is unavailable when every stored truck is past', () async {
      await store.write(
        foodTrucksSource,
        snapshot(trucks: [_truck('Taco Loco', '2026-10-01')]),
      );
      final body = await backend.fetch('/dining/food-trucks');

      expect(body['availability'], 'unavailable');
      expect(body['data'], isEmpty);
    });
  });

  group('trucks re-read', () {
    // the route answers by the campus month, as the backend does
    Map<String, dynamic> byMonth() => isFoodTruckSeason(CampusTime.wallDate(), defaultFoodTruckSeasonMonths)
        ? _body(_six)
        : _body(const [], availability: 'unavailable');

    final triggers = <String, void Function(ValueNotifier<int>, ValueNotifier<bool>)>{
      'a tick': (tick, tab) => tick.value++,
      'the tab becoming active': (tick, tab) {
        tab.value = false;
        tab.value = true;
      },
    };

    for (final entry in triggers.entries) {
      testWidgets('trucks fetched on Oct 31 are hidden on Nov 1 after ${entry.key}', (tester) async {
        RitClock.pin(DateTime.utc(2026, 11, 1, 3));
        final tick = ValueNotifier(0);
        final tab = ValueNotifier(true);
        await pumpDining(tester, null, backend: _Live(byMonth), tick: tick, tabActive: tab);
        expect(find.text('Taco Loco'), findsOneWidget);

        RitClock.pin(DateTime.utc(2026, 11, 1, 12));
        await tester.pumpAndSettle();
        expect(find.text('Taco Loco'), findsOneWidget);

        entry.value(tick, tab);
        await tester.pumpAndSettle();

        expect(find.text('Food trucks'), findsNothing);
        expect(find.text('Crossroads'), findsOneWidget);
      });
    }

    testWidgets('an aged out response is replaced by a newer available one', (tester) async {
      final live = _Live(() => _body(_six, age: const Duration(hours: 20)));
      final tick = ValueNotifier(0);
      await pumpDining(tester, null, backend: live, tick: tick);
      expect(find.text('Taco Loco'), findsNothing);

      live.answer = () => _body(_six);
      tick.value++;
      await tester.pumpAndSettle();

      expect(find.text('Taco Loco'), findsOneWidget);
    });

    testWidgets('a re-read with the same content moves nothing', (tester) async {
      final live = _Live(() => _body(_six));
      final tick = ValueNotifier(0);
      await pumpDining(tester, null, backend: live, tick: tick);
      final before = tester.getTopLeft(find.text('Crossroads'));
      final reads = live.reads;

      live.gate = Completer<void>();
      tick.value++;
      await tester.pump();
      await tester.pump();

      expect(live.reads, greaterThan(reads));
      expect(find.text('Taco Loco'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Crossroads')), before);

      live.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Taco Loco'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Crossroads')), before);
    });

    testWidgets('a tab that stays active does not re-read', (tester) async {
      final live = _Live(() => _body(_six));
      final tab = ValueNotifier(true);
      await pumpDining(tester, null, backend: live, tabActive: tab);
      final reads = live.reads;

      tab.value = true;
      await tester.pumpAndSettle();

      expect(live.reads, reads);
    });
  });

  group('at 2x text', () {
    testWidgets('scrolling to the trucks shows every place whole', (tester) async {
      await pumpDining(tester, _body(_six), size: const Size(390, 844), scale: 2);
      await tester.scrollUntilVisible(
        find.text('Curry Up'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(tester.takeException(), isNull);
      final place = find.text('Today · 11 a.m. to 2 p.m. · Global Village Plaza');
      expect(place, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(place).didExceedMaxLines, isFalse);
    });

    testWidgets('ensureVisible on the last truck row does not throw', (tester) async {
      await pumpDining(tester, _body(_six), size: const Size(390, 844), scale: 2);
      await tester.ensureVisible(find.text('Curry Up'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide layout shows a long place whole', (tester) async {
      const place = 'Behind the Gordon Field House beside the Global Village Plaza loading dock';
      await pumpDining(
        tester,
        _body([_truck('Taco Loco', '2026-10-14', time: '11 a.m. to 2 p.m.', place: place)]),
        size: const Size(700, 1600),
        scale: 2,
      );

      final text = find.text('Today · 11 a.m. to 2 p.m. · $place');
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.height, greaterThan(paragraph.preferredLineHeight * 1.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('header links', () {
    testWidgets('open exactly the two urls, externally', (tester) async {
      await pumpDining(tester, _body(const []));

      await tester.tap(find.text('Order online'));
      await tester.pump();
      await tester.tap(find.text('Check balance'));
      await tester.pump();

      expect(launcher.opened, ['https://ondemand.rit.edu/', 'https://tigerspend.rit.edu/']);
      expect(launcher.modes, everyElement(PreferredLaunchMode.externalApplication));
    });

    testWidgets('a failed launch copies the link and says so', (tester) async {
      launcher = _Launcher(succeeds: false);
      UrlLauncherPlatform.instance = launcher;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpDining(tester, _body(const []));

      await tester.tap(find.text('Check balance'));
      await tester.pump();
      await tester.pump();

      expect(copied, 'https://tigerspend.rit.edu/');
      expect(find.text('Check balance copied'), findsOneWidget);
    });

    for (final link in const [
      (label: 'Order online', url: 'https://ondemand.rit.edu/'),
      (label: 'Check balance', url: 'https://tigerspend.rit.edu/'),
    ]) {
      testWidgets('${link.label} is a labelled button with a 48pt target', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDining(tester, _body(const []));

        final node = tester.getSemantics(find.bySemanticsLabel(link.label));
        expect(node.label, link.label);
        expect(node.hint, 'Opens externally');
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isLink, isTrue);

        final box = tester.getRect(find.ancestor(of: find.text(link.label), matching: find.byType(InkWell)).first);
        expect(box.height, greaterThanOrEqualTo(48));
        expect(box.width, greaterThanOrEqualTo(48));
        handle.dispose();
      });
    }

    testWidgets('keyboard focus draws the 2px ring', (tester) async {
      await pumpDining(tester, _body(const []));
      expect(find.byKey(const ValueKey('focus-ring')), findsNothing);

      final order = find.widgetWithText(LinkButton, 'Order online');
      final balance = find.widgetWithText(LinkButton, 'Check balance');
      Finder ringIn(Finder pill) => find.descendant(of: pill, matching: find.byKey(const ValueKey('focus-ring')));

      for (var i = 0; i < 6 && ringIn(order).evaluate().isEmpty; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }

      expect(ringIn(order), findsOneWidget);
      expect(ringIn(balance), findsNothing);
      final decoration = tester.widget<DecoratedBox>(ringIn(order)).decoration as ShapeDecoration;
      expect((decoration.shape as RoundedRectangleBorder).side.width, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(ringIn(balance), findsOneWidget);
      expect(ringIn(order), findsNothing);
    });

    testWidgets('large text wraps the pills and keeps the full label', (tester) async {
      await pumpDining(tester, _body(const []), size: const Size(320, 700), scale: 2);

      expect(tester.takeException(), isNull);
      expect(find.text('Order online'), findsOneWidget);
      expect(find.text('Check balance'), findsOneWidget);
      for (final label in ['Order online', 'Check balance']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        final pill = tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);
        final text = tester.getRect(find.text(label));
        expect(pill.inflate(0.5).contains(text.topLeft), isTrue, reason: label);
        expect(pill.inflate(0.5).contains(text.bottomRight), isTrue, reason: label);
        expect(pill.right, lessThanOrEqualTo(320), reason: label);
      }
    });
  });

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 2.0]) {
        final name = 'dining_extras_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x';
        goldenWidgets(name, (tester) async {
          await pumpDining(tester, _body(_six), size: size, brightness: brightness, scale: scale);
          expect(find.text('Order online'), findsOneWidget);
          expect(find.text('Taco Loco'), findsOneWidget);
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name.png'));
        });
        if (scale == 2) {
          // the trucks sit below the fold at 2x text, so shoot the same width tall
          final tall = '${name}_tall';
          goldenWidgets(tall, (tester) async {
            await pumpDining(tester, _body(_six), size: Size(size.width, 2600), brightness: brightness, scale: scale);
            expect(find.text('Curry Up'), findsOneWidget);
            await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$tall.png'));
          });
        }
      }
    }
  }
}
