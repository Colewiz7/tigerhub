/// Setup as the iOS screenshots would show it: every step and the one-time
/// sheet, at both phone sizes and both text sizes, on the captured fixtures.
///
/// The repo keeps goldens for the default scheme. Set SETUP_SHOTS_DIR to also
/// write every scheme's screens as PNGs there, one folder per scheme, named the
/// same way. Nothing is written without it.
///
/// Regenerate with `flutter test --update-goldens test/setup_ios_golden_test.dart`
/// and look at every image before committing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/setup/mini_today.dart';
import 'package:tigerhub/screens/setup/setup_flow.dart';
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/whats_new_sheet.dart';

import 'golden_harness.dart';

Map<String, dynamic> _json(String name) => jsonDecode(File('test/golden/$name.json').readAsStringSync()) as Map<String, dynamic>;

List<T> _rows<T>(String name, T Function(Map<String, dynamic>) parse) => [
  for (final row in (_json(name)['data'] as List<dynamic>)) parse(row as Map<String, dynamic>),
];

final _shotsDir = Platform.environment['SETUP_SHOTS_DIR'];

// the keys the flow can write, emptied by hand as the cache keeps its first platform
const _keys = ['housing_area', 'housing_unit', 'dashboard_v2', 'color_scheme', 'pinned_dining', 'hidden_dining', 'hidden_dining_groups', 'dining_layout', 'setup_seen', 'hide_keywords', 'boost_keywords', 'keyword_rules_enabled'];

void main() {
  late List<HousingArea> areas;
  late List<DiningLocation> dining;
  late List<CampusEvent> events;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    for (final key in _keys) {
      await ResponseCache.instance.writeOrder(key, const []);
    }
    StaticConfig.overrideForTesting({
      'dining_groups': jsonDecode(File('assets/config/dining_groups.json').readAsStringSync()) as Map<String, dynamic>,
    });
    Preferences.instance.resetForTests();
    await Preferences.instance.load();
    areas = _rows('housing_areas', HousingArea.fromJson);
    dining = _rows('dining', DiningLocation.fromJson);
    events = _rows('events', CampusEvent.fromJson);
  });
  tearDown(Preferences.instance.resetForTests);

  final boundary = GlobalKey();

  Future<void> pump(WidgetTester tester, Size size, double scale, AppScheme choice, Widget Function(SchemeController) home) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final scheme = SchemeController(initial: choice);
    addTearDown(scheme.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ListenableBuilder(
          listenable: scheme,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.from(scheme.scheme).copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: home(scheme),
          ),
        ),
      ),
    );
    // the mark decodes off the test clock
    final mark = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/images/tigerhub-mascot.png'), mark));
    await tester.pumpAndSettle();
  }

  String shotName(String step, Size size, double scale) => 'setup_${step}_ios_${size.width.toInt()}x${size.height.toInt()}_dark_${scale.toInt()}x';

  // the repo's golden for the default scheme, a PNG in the shots folder for every scheme
  Future<void> shoot(WidgetTester tester, AppScheme choice, String step, Size size, double scale) async {
    final name = shotName(step, size, scale);
    if (choice == AppScheme.espresso) {
      await expectLater(find.byKey(boundary), matchesGoldenFile('goldens/$name.png'));
    }
    final dir = _shotsDir;
    if (dir == null) return;
    final bytes = await tester.runAsync(() async {
      final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundary));
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final folder = Directory('$dir/${choice.id}')..createSync(recursive: true);
    File('${folder.path}/$name.png').writeAsBytesSync(bytes!);
  }

  Future<void> advance(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  // a tap on something below the fold, then back to the top for the picture
  Future<void> pick(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final scale in const [1.0, 2.0]) {
      for (final choice in AppScheme.values) {
        final label = 'setup flow ${choice.id} ${size.width.toInt()}x${size.height.toInt()} ${scale.toInt()}x';
        goldenWidgets(label, (tester) async {
          await pump(
            tester,
            size,
            scale,
            choice,
            (scheme) => SetupFlow(scheme: scheme, areas: areas, dining: dining, events: events, onDone: () {}),
          );
          await shoot(tester, choice, 'welcome', size, scale);

          await advance(tester);
          await pick(tester, find.text(choice.label));
          await shoot(tester, choice, 'look', size, scale);

          await advance(tester);
          await pick(tester, find.text('Global Village'));
          await shoot(tester, choice, 'home', size, scale);

          await advance(tester);
          await pick(tester, find.text("Gracie's"));
          await pick(tester, find.text('Beanz'));
          await shoot(tester, choice, 'spots', size, scale);

          await advance(tester);
          await pick(tester, find.text('Low key'));
          await shoot(tester, choice, 'events', size, scale);

          await advance(tester);
          await shoot(tester, choice, 'today', size, scale);

          await advance(tester);
          await shoot(tester, choice, 'done', size, scale);
        });

        goldenWidgets('$label whats new', (tester) async {
          await pump(
            tester,
            size,
            scale,
            choice,
            // the app behind the sheet, drawn at the phone's own width
            (scheme) => Scaffold(
              body: LayoutBuilder(
                builder: (context, box) => MiniScreen(
                  displayWidth: box.maxWidth,
                  displayHeight: box.maxHeight,
                  height: 390 * box.maxHeight / box.maxWidth,
                  child: const MiniToday(),
                ),
              ),
            ),
          );
          unawaited(showWhatsNewSheet(tester.element(find.byType(Scaffold))));
          await tester.pumpAndSettle();
          await shoot(tester, choice, 'whatsnew', size, scale);
        });
      }
    }
  }
}
