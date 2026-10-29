/// The built-in schemes: every text pair that matters holds 4.5:1 in each dark
/// palette, light is untouched, the choice persists, and nothing follows the
/// OS or the wallpaper.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dark_palette.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/theme/semantic.dart';

import 'support/contrast.dart';

typedef Pair = (String, Color, Color);

List<Pair> darkPairs(ThemeData theme) {
  final s = theme.colorScheme;
  final sem = theme.extension<Semantic>()!;
  final bg = s.surfaceContainerLowest;
  final surface = s.surfaceContainerLow;
  final elevated = s.surfaceContainerHigh;
  // tab_bar.dart: surfaceContainer at 0.7 over the page, pill is secondaryContainer
  final glass = Color.alphaBlend(s.surfaceContainer.withValues(alpha: 0.7), bg);
  return [
    ('Text on Bg', s.onSurface, bg),
    ('Text on Surface', s.onSurface, surface),
    ('Text on Elevated', s.onSurface, elevated),
    ('Muted on Bg', s.onSurfaceVariant, bg),
    ('Muted on Surface', s.onSurfaceVariant, surface),
    ('Muted on Elevated', s.onSurfaceVariant, elevated),
    ('Accent on Bg', s.primary, bg),
    ('Accent on Surface', s.primary, surface),
    ('Accent on Elevated', s.primary, elevated),
    ('On-accent on Accent fill', s.onPrimary, s.primary),
    ('Open chip', sem.open, sem.openContainer),
    ('Busy chip', sem.busy, sem.busyContainer),
    ('Closed chip', sem.closed, sem.closedContainer),
    ('Closed on Surface', sem.closed, surface),
    ('Time highlight', s.onSurface, Color.alphaBlend(s.primary.withValues(alpha: 0.12), surface)),
    ('Selected tab label on pill', s.primary, s.secondaryContainer),
    ('Unselected tab label on glass', s.onSurfaceVariant, glass),
  ];
}

ThemeData themeFor(AppScheme choice) => AppTheme.from(SchemeController.forChoice(choice));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  for (final choice in AppScheme.values.where((s) => s.palette != null)) {
    group('${choice.label} palette', () {
      final theme = themeFor(choice);

      test('is dark and maps to its roles', () {
        final p = choice.palette!;
        final s = theme.colorScheme;
        expect(s.brightness, Brightness.dark);
        expect(s.surfaceContainerLowest, p.bg);
        expect(s.surfaceContainerLow, p.surface);
        expect(s.surfaceContainerHigh, p.elevated);
        expect(s.onSurface, p.text);
        expect(s.onSurfaceVariant, p.muted);
        expect(s.primary, p.accent);
      });

      test('every pair holds 4.5:1', () {
        for (final (label, fg, bg) in darkPairs(theme)) {
          expect(ratio(fg, bg), greaterThanOrEqualTo(4.5), reason: '$label ${hex(fg)} on ${hex(bg)}');
        }
      });

      test('semantic uses the palette success and busy', () {
        final sem = theme.extension<Semantic>()!;
        final p = choice.palette!;
        expect(sem.open, p.success);
        expect(sem.busy, p.busy);
        expect(sem.openContainer, p.chip(p.success));
        expect(sem.busyContainer, p.chip(p.busy));
      });

      test('surface steps are separable', () {
        final s = theme.colorScheme;
        final levels = [
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ];
        for (var i = 1; i < levels.length; i++) {
          expect(levels[i], isNot(levels[i - 1]), reason: 'step $i');
        }
      });
    });
  }

  test('the espresso palette is the recommended one', () {
    const p = DarkPalette.espresso;
    expect(
      [p.bg, p.surface, p.elevated, p.text, p.muted, p.accent, p.success, p.busy].map(hex),
      ['140A08', '2A1E1A', '382A25', 'F2E6DE', 'C6B3A8', 'F3B08F', '81AF7D', 'C7942F'],
    );
  });

  test('a scheme that is not a palette gets the nudged status colours', () {
    final other = ColorScheme.fromSeed(seedColor: const Color(0xFF3366CC), brightness: Brightness.dark);
    expect(DarkPalette.of(other), isNull);
    for (final p in DarkPalette.all) {
      expect(Semantic.from(other).open, isNot(p.success));
    }
  });

  group('light scheme', () {
    final light = themeFor(AppScheme.light);

    test('is the plain seed scheme', () {
      final seeded = ColorScheme.fromSeed(seedColor: SchemeController.fallbackSeed, brightness: Brightness.light);
      expect(SchemeController.builtIn(Brightness.light), seeded);
      expect(SchemeController.forChoice(AppScheme.light), seeded);
      expect(DarkPalette.of(seeded), isNull);
    });

    test('status colours are unchanged', () {
      final sem = light.extension<Semantic>()!;
      expect(
        [hex(sem.open), hex(sem.onOpen), hex(sem.openContainer), hex(sem.closed), hex(sem.closedContainer), hex(sem.busy), hex(sem.onBusy), hex(sem.busyContainer)],
        ['589B44', '073900', 'ADF592', '782F28', 'FFDAD5', '996100', '462A00', 'FFDDB7'],
      );
    });
  });

  test('status colours differ between dark and light', () {
    final d = themeFor(AppScheme.espresso).extension<Semantic>()!, l = themeFor(AppScheme.light).extension<Semantic>()!;
    expect(d.open, isNot(l.open));
    expect(d.busy, isNot(l.busy));
    expect(d.openContainer, isNot(l.openContainer));
  });

  group('selection', () {
    test('defaults to Espresso', () async {
      final controller = SchemeController();
      await controller.load();
      expect(controller.choice, AppScheme.espresso);
      controller.dispose();
    });

    test('persists across a restart', () async {
      for (final choice in AppScheme.values) {
        final first = SchemeController();
        await first.select(choice);
        first.dispose();
        final second = SchemeController();
        await second.load();
        expect(second.choice, choice);
        expect(second.scheme, SchemeController.forChoice(choice));
        second.dispose();
      }
    });

    test('an unknown stored id falls back to Espresso', () {
      expect(AppScheme.parse('wallpaper'), AppScheme.espresso);
      expect(AppScheme.parse(null), AppScheme.espresso);
    });

    test('selecting notifies listeners once', () async {
      final controller = SchemeController();
      var calls = 0;
      controller.addListener(() => calls++);
      await controller.select(AppScheme.mocha);
      await controller.select(AppScheme.mocha);
      expect(calls, 1);
      controller.dispose();
    });
  });

  test('no code path follows the system or the wallpaper', () {
    final banned = RegExp(
      r'ThemeMode\.system|platformBrightness|darkTheme:|Caelestia|caelestia|schemeFromJson|watchScheme|readScheme|FORCE_SEED|setForceSeed',
    );
    final hits = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (banned.hasMatch(line)) hits.add('${file.path}:${i + 1}: $line');
      }
    }
    expect(hits, isEmpty);
    expect(File('lib/theme/scheme_source.dart').existsSync(), isFalse);
    expect(File('lib/theme/scheme_source_io.dart').existsSync(), isFalse);
  });
}
