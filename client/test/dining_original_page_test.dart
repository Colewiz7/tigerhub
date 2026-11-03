/// A dining location can open its RIT page in the browser, never in a webview,
/// and copies the link when nothing can open it.
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
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/dining_detail_sheet.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends MethodChannelUrlLauncher with MockPlatformInterfaceMixin {
  _Launcher({required this.succeeds});

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

class _EmptyMenu implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {
    'service_date': '2026-11-03',
    'location_id': 23,
    'dishes': <Object>[],
  };

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Literal on purpose: changing a link in the table must fail here.
  const expected = {
    21: 'https://www.rit.edu/dining/location/gracies',
    22: 'https://www.rit.edu/dining/location/kitchen-brick-city',
    23: 'https://www.rit.edu/dining/location/cafe-and-market-crossroads',
    24: 'https://www.rit.edu/dining/location/commons',
    25: 'https://www.rit.edu/dining/location/patio-global-village',
    26: 'https://www.rit.edu/dining/location/ritz',
    27: 'https://www.rit.edu/dining/location/corner-store',
    29: 'https://www.rit.edu/dining/location/market-global-village',
    30: 'https://www.rit.edu/dining/location/artesano-bakery-cafe',
    31: 'https://www.rit.edu/dining/location/beanz',
    32: 'https://www.rit.edu/dining/location/ben-and-jerrys',
    34: 'https://www.rit.edu/dining/location/ctrl-alt-deli',
    35: 'https://www.rit.edu/dining/location/college-grind',
    36: 'https://www.rit.edu/dining/location/nathans-soup-salad',
    37: 'https://www.rit.edu/dining/location/javas',
    38: 'https://www.rit.edu/dining/location/midnight-oil',
    41: 'https://www.rit.edu/dining/directory',
    441: 'https://www.rit.edu/dining/location/loaded-latke',
    461: 'https://www.rit.edu/dining/location/petals-restaurant',
    481: 'https://www.rit.edu/dining/location/bytes',
    501: 'https://www.rit.edu/dining/food-trucks',
  };
  const fallback = 'https://www.rit.edu/dining/locations';

  late UrlLauncherPlatform previous;
  late StaticConfig config;

  setUp(() {
    previous = UrlLauncherPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final table = jsonDecode(File('assets/config/dining_links.json').readAsStringSync()) as Map<String, dynamic>;
    StaticConfig.overrideForTesting({'dining_links': table});
    config = StaticConfig.instance;
  });
  tearDown(() {
    UrlLauncherPlatform.instance = previous;
    StaticConfig.overrideForTesting({});
  });

  test('the table says when it was verified', () {
    final table = jsonDecode(File('assets/config/dining_links.json').readAsStringSync()) as Map<String, dynamic>;
    expect(table['last_verified'], '2026-11-03');
  });

  test('every location has the literal URL, and others get the index', () {
    for (final entry in expected.entries) {
      expect(config.diningPageUrl(entry.key), entry.value, reason: '${entry.key}');
    }
    expect(config.diningPageUrl(28), fallback);
    expect(config.diningPageUrl(61), fallback);
    expect(config.diningPageUrl(39), fallback);
  });

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);
    final location = DiningLocation.fromJson({'id': 23, 'name': 'Crossroads', 'is_open': true});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiningDetailSheet(location: location, api: ApiClient(backend: _EmptyMenu())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final button = find.byKey(const ValueKey('open-original-page'));

  testWidgets('opens the Crossroads page in the browser', (tester) async {
    final launcher = _Launcher(succeeds: true);
    UrlLauncherPlatform.instance = launcher;
    await pump(tester);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(launcher.opened, [expected[23]]);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
  });

  testWidgets('copies the link when nothing opens it', (tester) async {
    UrlLauncherPlatform.instance = _Launcher(succeeds: false);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pump(tester);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, expected[23]);
    expect(find.text('Link copied'), findsOneWidget);
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('48pt target with a link label at ${scale}x', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, scale: scale);
      await tester.ensureVisible(button);

      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(button),
        matchesSemantics(label: 'Open original page', isLink: true, hasTapAction: true),
      );
      handle.dispose();
    });
  }

  testWidgets('no button before the table is loaded', (tester) async {
    StaticConfig.overrideForTesting({});
    await pump(tester);
    expect(button, findsNothing);
  });
}
