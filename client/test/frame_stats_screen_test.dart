import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/screens/settings/about_section.dart';
import 'package:tigerhub/screens/settings/frame_stats_screen.dart';
import 'package:tigerhub/services/frame_monitor.dart';
import 'package:tigerhub/services/frame_stats.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

import 'golden_harness.dart';

FrameStats sampleStats() {
  final s = FrameStats();
  var t = 0;
  void frames(int n, int build, int raster) {
    for (var i = 0; i < n; i++) {
      s.recordFrame(atUs: t, buildUs: build, rasterUs: raster);
      t += 8333;
    }
  }

  frames(900, 1200, 2100);
  for (var tab = 0; tab < s.tabs; tab++) {
    s.tabSwitched(tab, t);
    frames(20, 2000 + tab * 900, 3000 + tab * 700);
    s.scrollStarted(tab, t);
    frames(60, 1500 + tab * 300, 2500);
    s.scrollEnded(t);
  }
  frames(10, 9000, 12000);
  return s;
}

Widget app(Widget home, {Brightness brightness = Brightness.light, double scale = 1}) =>
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          theme: AppTheme.from(SchemeController.builtIn(brightness)),
          home: home,
        ),
      ),
    );

void main() {
  group('opening from About', () {
    Future<void> pumpAbout(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const Scaffold(body: AboutSection())));
      await tester.pump();
    }

    Future<void> tapVersion(WidgetTester tester, int times, {Duration gap = const Duration(milliseconds: 100)}) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.text('Version'));
        await tester.pump(gap);
      }
    }

    testWidgets('four taps do nothing', (tester) async {
      await pumpAbout(tester);
      await tapVersion(tester, 4);
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsNothing);
    });

    testWidgets('five taps open the screen', (tester) async {
      await pumpAbout(tester);
      await tapVersion(tester, 5);
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsOneWidget);
      expect(find.text('Frame stats'), findsOneWidget);
    });

    testWidgets('slow taps never add up', (tester) async {
      await pumpAbout(tester);
      await tapVersion(tester, 6, gap: const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsNothing);
    });

    testWidgets('a pause resets the count', (tester) async {
      await pumpAbout(tester);
      await tapVersion(tester, 3);
      await tester.pump(const Duration(milliseconds: 1200));
      await tapVersion(tester, 4);
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsNothing);
      await tapVersion(tester, 1);
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsOneWidget);
    });

    testWidgets('the count starts over after opening', (tester) async {
      await pumpAbout(tester);
      await tapVersion(tester, 5);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsNothing);
      await tapVersion(tester, 4);
      await tester.pumpAndSettle();
      expect(find.byType(FrameStatsScreen), findsNothing);
    });
  });

  group('screen', () {
    Future<void> pumpScreen(WidgetTester tester, FrameStats stats) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(FrameStatsScreen(stats: stats)));
      await tester.pump();
    }

    testWidgets('shows the numbers and every tab', (tester) async {
      await pumpScreen(tester, sampleStats());
      expect(find.text('Frames'), findsOneWidget);
      expect(find.text('Over 8.3 ms'), findsOneWidget);
      expect(find.text('Over 16.7 ms'), findsOneWidget);
      expect(find.text('Worst frame'), findsOneWidget);
      for (final name in frameTabNames) {
        expect(find.text(name), findsNWidgets(2));
      }
    });

    testWidgets('reset clears the stats', (tester) async {
      final stats = sampleStats();
      await pumpScreen(tester, stats);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(stats.summary().frames, 0);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('copy puts the report on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpScreen(tester, sampleStats());
      await tester.tap(find.text('Copy report'));
      await tester.pump();
      expect(copied, contains('TigerHub'));
      expect(copied, contains('Text scale 1.00'));
      expect(copied, contains('Tab switch (first 500 ms)'));
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copy report'), findsOneWidget);
    });

    testWidgets('refreshes on a timer and pauses recording while open', (tester) async {
      final stats = FrameStats();
      await pumpScreen(tester, stats);
      final monitor = FrameMonitor.instance;
      monitor.stats.reset();
      // A frame that starts while the screen is open is not counted.
      monitor.stats.recordFrame(atUs: monitor.nowUs + 1000, buildUs: 1, rasterUs: 1);
      expect(monitor.stats.summary().frames, 0);
      stats.recordFrame(atUs: 0, buildUs: 1000, rasterUs: 1000);
      expect(find.text('1'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      monitor.stats.recordFrame(atUs: monitor.nowUs + 1000000, buildUs: 1, rasterUs: 1);
      expect(monitor.stats.summary().frames, 1);
      monitor.stats.reset();
    });

    testWidgets('buttons are at least 48pt with labels', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, sampleStats());
      for (final label in ['Reset', 'Copy report', 'Back']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      for (final label in ['Reset', 'Copy report']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
      }
      final back = tester.getSize(
        find.ancestor(of: find.byIcon(Icons.arrow_back_rounded), matching: find.byType(ConstrainedBox)).first,
      );
      expect(back.height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });

    testWidgets('the keyboard focus ring shows', (tester) async {
      await pumpScreen(tester, sampleStats());
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byKey(const ValueKey('focus-ring')), findsOneWidget);
    });
  });

  for (final size in const [Size(390, 844), Size(440, 956)]) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 2.0]) {
        final name = 'frame_stats_${size.width.toInt()}x${size.height.toInt()}_${brightness.name}_${scale.toInt()}x.png';
        goldenWidgets(name, (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(app(
            FrameStatsScreen(
              stats: sampleStats(),
              device: const ['ios 18.2', 'Refresh 120 Hz'],
            ),
            brightness: brightness,
            scale: scale,
          ));
          await tester.pump();
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
          // The lower cards too, which the first screenful hides.
          await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -5000));
          await tester.pump();
          final low = name.replaceFirst('.png', '_end.png');
          await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$low'));
        });
      }
    }
  }
}
