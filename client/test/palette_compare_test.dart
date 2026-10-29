/// Dark palette comparison. Not a theme switch: nothing here is reachable from
/// the app.
///
/// The contrast table always runs, so a palette with a broken role fails the
/// suite. Set PALETTE_SHOTS to a directory to also write the screens, one
/// folder per palette, and PALETTE_REPORT to a file path to write the contrast
/// report. Light mode is not touched.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/data/shuttles.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/theme/semantic.dart';

import 'golden_harness.dart';
import 'support/contrast.dart';
import 'support/palette_options.dart';
import 'support/tabs.dart';

final _now = DateTime.utc(2026, 8, 30, 16, 30);

const _cards = [
  CardInstance(id: 'dining-0', type: ModuleType.diningStatus),
  CardInstance(id: 'events-0', type: ModuleType.generalEvents),
  CardInstance(id: 'shuttles-0', type: ModuleType.shuttles, size: CardSize.compact),
  CardInstance(id: 'chefs-0', type: ModuleType.visitingChefs, size: CardSize.compact),
  CardInstance(id: 'facility-0', type: ModuleType.facilityHours, size: CardSize.compact, scope: 'Judson/Hale Aquatics Center'),
  CardInstance(id: 'package-0', type: ModuleType.packagePickup, size: CardSize.compact),
];

Map<String, dynamic> _json(String name) => jsonDecode(File('test/golden/$name.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _openAt(Map<String, dynamic> body, DateTime now) {
  for (final loc in (body['data'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final spans = (loc['today'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final current = spans.where((s) => !now.isBefore(DateTime.parse(s['opens_at'] as String)) && now.isBefore(DateTime.parse(s['closes_at'] as String)));
    final next = spans.where((s) => now.isBefore(DateTime.parse(s['opens_at'] as String)));
    loc['is_open'] = current.isNotEmpty;
    loc['closes_at'] = current.isEmpty ? null : current.first['closes_at'];
    loc['opens_at'] = next.isEmpty ? null : next.first['opens_at'];
    loc['next_transition'] = loc['closes_at'] ?? loc['opens_at'];
  }
  return body;
}

class _FixtureBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]) async => switch (path) {
    '/dining' => _openAt(_json('dining'), _now),
    '/events' => _json('events'),
    '/dining/visiting-chefs' => _json('dining_visiting-chefs'),
    '/housing/areas' => _json('housing_areas'),
    '/post-offices' => _json('post-offices'),
    '/recreation/hours' => _json('recreation_hours'),
    '/makerspace/hours' => {'items': <dynamic>[]},
    _ when path.endsWith('/address') => throw const SocketException('not in the fixtures'),
    _ => {'data': <dynamic>[], 'stale': false, 'last_updated': null},
  };

  @override
  void close() {}
}

/// What each palette is judged on, as (label, foreground, background).
typedef Pair = (String, Color, Color);

List<Pair> pairsFor(ThemeData theme) {
  final s = theme.colorScheme;
  final sem = theme.extension<Semantic>()!;
  final bg = s.surfaceContainerLowest;
  final surface = s.surfaceContainerLow;
  final elevated = s.surfaceContainerHigh;
  final glass = Color.alphaBlend(s.surfaceContainer.withValues(alpha: 0.7), bg);
  return [
    ('Text on Bg', s.onSurface, bg),
    ('Text on Surface', s.onSurface, surface),
    ('Text on Elevated', s.onSurface, elevated),
    ('Muted on Bg', s.onSurfaceVariant, bg),
    ('Muted on Surface', s.onSurfaceVariant, surface),
    ('Muted on Elevated', s.onSurfaceVariant, elevated),
    ('Accent text on Bg', s.primary, bg),
    ('Accent text on Surface', s.primary, surface),
    ('Accent text on Elevated', s.primary, elevated),
    ('On-accent text on Accent fill', s.onPrimary, s.primary),
    ('Open chip (N% full)', sem.open, sem.openContainer),
    ('Busy chip', sem.busy, sem.busyContainer),
    ('Time highlight text', s.onSurface, Color.alphaBlend(s.primary.withValues(alpha: 0.12), surface)),
    ('Selected tab label on pill', s.primary, s.secondaryContainer),
    ('Unselected tab label on glass', s.onSurfaceVariant, glass),
    ('Accent hero text (N today) on Surface', s.primary, surface),
  ];
}

/// Everything compared, the current dark theme first.
Map<String, ThemeData> _themes() => {
  'baseline-current': AppTheme.from(SchemeController.builtIn(Brightness.dark)),
  for (final p in paletteOptions) p.name: p.theme(AppTheme.from),
};

String contrastReport() {
  final out = StringBuffer('# Dark palette contrast\n\nWCAG ratios. Text needs 4.5:1. "Fix" is the same hue and saturation moved in lightness until it passes.\n');
  for (final entry in _themes().entries) {
    out.writeln('\n## ${entry.key}\n');
    out.writeln('| Pair | Fg | Bg | Ratio | Result | Fix |');
    out.writeln('|---|---|---|---|---|---|');
    for (final (label, fg, bg) in pairsFor(entry.value)) {
      final r = ratio(fg, bg);
      final ok = r >= 4.5;
      final fix = ok ? '' : '#${hex(adjustToContrast(fg, bg))}';
      out.writeln('| $label | #${hex(fg)} | #${hex(bg)} | ${r.toStringAsFixed(2)} | ${ok ? 'pass' : 'FAIL'} | $fix |');
    }
  }
  return out.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shotsDir = Platform.environment['PALETTE_SHOTS'];
  final reportPath = Platform.environment['PALETTE_REPORT'];

  group('palette contrast', () {
    test('every palette defines every role and ratios are finite', () {
      for (final entry in _themes().entries) {
        final pairs = pairsFor(entry.value);
        expect(pairs, isNotEmpty, reason: entry.key);
        for (final (label, fg, bg) in pairs) {
          expect(ratio(fg, bg), inInclusiveRange(1, 21), reason: '${entry.key} $label');
        }
      }
    });

    test('the adjuster reaches the target', () {
      final fixed = adjustToContrast(const Color(0xFF8A7A3A), const Color(0xFF3A2C27));
      expect(ratio(fixed, const Color(0xFF3A2C27)), greaterThanOrEqualTo(4.5));
    });

    test('light mode is not changed by the palette options', () {
      final before = SchemeController.builtIn(Brightness.light);
      paletteOptions.first.theme(AppTheme.from);
      expect(SchemeController.builtIn(Brightness.light), before);
    });

    test('write the report', () {
      if (reportPath == null) return;
      File(reportPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contrastReport());
    });
  });

  if (shotsDir == null) return;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
    RitClock.pin(_now);
    ShuttleSchedule.overrideForTesting(ShuttleSchedule.parse(jsonDecode(File('assets/config/shuttles.json').readAsStringSync()) as Map<String, dynamic>));
    StaticConfig.overrideForTesting({
      for (final name in ['dining_categories', 'post_offices', 'housing_areas', 'shed_hours', 'fd_locations'])
        name: jsonDecode(File('assets/config/$name.json').readAsStringSync()) as Map<String, dynamic>,
    });
  });
  tearDown(() {
    RitClock.reset();
    ShuttleSchedule.overrideForTesting(null);
    Preferences.instance.resetForTests();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> shoot(WidgetTester tester, GlobalKey key, String path) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final entry in _themes().entries) {
    for (final size in const [Size(390, 844), Size(440, 956)]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      goldenWidgets('${entry.key} $tag', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        await Preferences.instance.markSetupSeen();
        await Preferences.instance.setHome(area: 'global-village');
        await Preferences.instance.togglePinned(23);
        await DashboardStore.save(_cards);
        final scheme = SchemeController();
        addTearDown(scheme.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.noScaling),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: entry.value.copyWith(platform: TargetPlatform.iOS),
              home: AppShell(api: ApiClient(backend: _FixtureBackend()), scheme: scheme),
            ),
          ),
        ));
        final mark = tester.element(find.byType(AppShell));
        await tester.runAsync(() => precacheImage(const AssetImage('assets/images/tigerhub-mascot.png'), mark));
        await settle(tester);

        final dir = '$shotsDir/${entry.key}';
        await shoot(tester, key, '$dir/today_$tag.png');

        await tester.tap(find.byTooltip('Settings'));
        await settle(tester);
        await shoot(tester, key, '$dir/settings_$tag.png');

        for (final tab in const ['Dining', 'Events', 'Campus']) {
          await tester.tap(tabLabel(tab));
          await settle(tester);
          await shoot(tester, key, '$dir/${tab.toLowerCase()}_$tag.png');
        }
      });
    }
  }
}
