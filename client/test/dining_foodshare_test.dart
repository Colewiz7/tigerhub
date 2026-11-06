/// RIT FoodShare in Dining: weekly hours, today's state, placement and filters.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/foodshare.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'golden_harness.dart';
import 'support/dining_harness.dart';

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

// campus wall clock to the instant it names, whatever the device zone is
DateTime _at(int month, int day, int hour, [int minute = 0, int second = 0]) =>
    CampusTime.wall(2026, month, day, hour, minute, second);

String _text(DateTime instant) => foodShareStatusAt(instant).text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hours table', () {
    test('carries the source and the day it was checked', () {
      expect(foodShareSourceUrl, 'https://www.rit.edu/lead/rit-foodshare');
      expect(foodShareLastVerified, '2026-11-06');
      expect(DateTime.tryParse(foodShareLastVerified)?.toIso8601String().substring(0, 10), foodShareLastVerified);
      expect(foodShareAddress, '113 Kimball Drive, Riverknoll Apartments');
      expect(foodShareHours.keys.toSet(), {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.saturday});
      for (final day in [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday]) {
        expect(foodShareHours[day], (opens: 13, closes: 19));
      }
      expect(foodShareHours[DateTime.saturday], (opens: 13, closes: 17));
    });

    test('Monday to Thursday, 1 PM to 7 PM, at the boundaries', () {
      // Mon Nov 2 2026, EST
      expect(_text(_at(11, 2, 0)), 'Opens 1 PM');
      expect(_text(_at(11, 2, 12, 59, 59)), 'Opens 1 PM');
      expect(_text(_at(11, 2, 13)), 'Open until 7 PM');
      expect(_text(_at(11, 2, 18, 59, 59)), 'Open until 7 PM');
      expect(_text(_at(11, 2, 19)), 'Closed today');
      expect(_text(_at(11, 2, 23, 59, 59)), 'Closed today');
      for (final day in [3, 4, 5]) {
        expect(_text(_at(11, day, 13)), 'Open until 7 PM', reason: 'Nov $day');
        expect(_text(_at(11, day, 19)), 'Closed today', reason: 'Nov $day');
      }
      expect(foodShareStatusAt(_at(11, 5, 18, 59)).phase, FoodSharePhase.open);
    });

    test('Saturday closes at 5 PM', () {
      expect(_text(_at(11, 7, 12, 59)), 'Opens 1 PM');
      expect(_text(_at(11, 7, 13)), 'Open until 5 PM');
      expect(_text(_at(11, 7, 16, 59, 59)), 'Open until 5 PM');
      expect(_text(_at(11, 7, 17)), 'Closed today');
    });

    test('Friday and Sunday are closed all day', () {
      for (final day in [6, 8]) {
        for (final hour in [0, 9, 13, 15, 18, 19, 23]) {
          final status = foodShareStatusAt(_at(11, day, hour));
          expect(status.text, 'Closed today', reason: 'Nov $day $hour:00');
          expect(status.phase, FoodSharePhase.closed);
        }
      }
    });

    test('daylight time uses the same wall clock', () {
      // Wed Oct 14 2026, EDT
      expect(_text(_at(10, 14, 12, 59)), 'Opens 1 PM');
      expect(_text(_at(10, 14, 13)), 'Open until 7 PM');
      expect(_text(_at(10, 14, 19)), 'Closed today');
      // clocks go back Sun Nov 1, so Mon Nov 2 keeps the 1 PM start in EST
      expect(_text(DateTime.utc(2026, 11, 2, 17, 59)), 'Opens 1 PM');
      expect(_text(DateTime.utc(2026, 11, 2, 18)), 'Open until 7 PM');
    });

    test('the campus day decides, not the UTC day or the device day', () {
      // 6:30 PM Monday in New York is already Tuesday 23:30 UTC the next day
      // in Tokyo and Monday 15:30 in Los Angeles
      final monEvening = DateTime.utc(2026, 11, 2, 23, 30);
      expect(_text(monEvening), 'Open until 7 PM');
      // 8 PM Monday campus is Tuesday 01:00 UTC
      expect(_text(DateTime.utc(2026, 11, 3, 1)), 'Closed today');
      // 4:59 PM Saturday campus is still Saturday in UTC, 5 PM is not open
      expect(_text(DateTime.utc(2026, 11, 7, 21, 59)), 'Open until 5 PM');
      expect(_text(DateTime.utc(2026, 11, 7, 22)), 'Closed today');
      // 7:30 PM Thursday campus is Friday 00:30 UTC, and it is closed either way
      expect(_text(DateTime.utc(2026, 11, 6, 0, 30)), 'Closed today');
      // 10 AM Friday in New York is Thursday night in Los Angeles, not open
      expect(_text(DateTime.utc(2026, 11, 6, 15)), 'Closed today');
      // 9 AM Saturday in Tokyo is Friday 8 PM campus: closed, not Opens 1 PM
      expect(_text(DateTime.utc(2026, 11, 7, 0)), 'Closed today');
    });

    test('words match the search box', () {
      expect(foodShareMatches(''), isTrue);
      expect(foodShareMatches('food'), isTrue);
      expect(foodShareMatches('Pantry'), isTrue);
      expect(foodShareMatches('foodsh'), isTrue);
      expect(foodShareMatches('crossroads'), isFalse);
    });

    test('copy has no dashes and no all caps', () {
      for (final line in [foodShareLabel, foodShareKind, foodShareNote, _text(_at(11, 2, 14)), _text(_at(11, 2, 8)), _text(_at(11, 6, 14))]) {
        expect(line, isNot(contains('—')));
        expect(line, isNot(contains('–')));
        expect(line, isNot(matches(RegExp(r'^[A-Z0-9 ]+$'))));
      }
    });
  });

  group('Dining tab', () {
    late _Launcher launcher;
    late UrlLauncherPlatform previousLauncher;

    setUpDining();
    setUp(() {
      previousLauncher = UrlLauncherPlatform.instance;
      launcher = _Launcher();
      UrlLauncherPlatform.instance = launcher;
    });
    tearDown(() => UrlLauncherPlatform.instance = previousLauncher);

    final row = find.byKey(const ValueKey('foodshare'));
    // Wed Oct 14 2026, 1 PM campus
    final open = _at(10, 14, 13);

    Future<void> showAll(WidgetTester tester) async {
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
    }

    testWidgets('sits below the places', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      await showAll(tester);
      expect(row, findsOneWidget);
      expect(find.text('Free food pantry'), findsOneWidget);
      expect(find.text('Open until 7 PM · Hours may change'), findsOneWidget);
      expect(find.text('FoodShare'), findsOneWidget);
      // below the last place row
      final lastPlace = find.byKey(const ValueKey('place-461'));
      expect(lastPlace, findsOneWidget);
      expect(tester.getTopLeft(row).dy, greaterThan(tester.getBottomLeft(lastPlace).dy));
    });

    testWidgets('shows the state for the hour: opens later, open, closed', (tester) async {
      RitClock.pin(_at(10, 14, 9));
      await pumpDiningScreen(tester);
      await showAll(tester);
      expect(find.text('Opens 1 PM · Hours may change'), findsOneWidget);

      RitClock.pin(_at(10, 14, 20));
      await pumpDiningScreen(tester);
      await showAll(tester);
      expect(find.text('Closed today · Hours may change'), findsOneWidget);

      RitClock.pin(_at(10, 16, 14));
      await pumpDiningScreen(tester);
      await showAll(tester);
      expect(find.text('Closed today · Hours may change'), findsOneWidget);
    });

    testWidgets('Open now lists it while open and drops it when closed', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      expect(row, findsOneWidget);

      RitClock.pin(_at(10, 14, 9));
      await pumpDiningScreen(tester);
      expect(row, findsNothing);
    });

    testWidgets('Favorites never lists it, All always does', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(row, findsNothing);
      await showAll(tester);
      expect(row, findsOneWidget);
    });

    testWidgets('search finds it by name and drops it for other words', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      await showAll(tester);
      await tester.enterText(find.byType(EditableText), 'pantry');
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'crossroads');
      await tester.pumpAndSettle();
      expect(row, findsNothing);
    });

    testWidgets('a venue type filter drops it', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      await showAll(tester);
      expect(row, findsOneWidget);
      await tester.tap(find.byType(FilterChip).first);
      await tester.pumpAndSettle();
      expect(row, findsNothing);
    });

    testWidgets('hiding Dorm side does not touch it', (tester) async {
      RitClock.pin(open);
      await Preferences.instance.setGroupHidden('dorm_side', true);
      await pumpDiningScreen(tester);
      expect(row, findsOneWidget);
      await showAll(tester);
      expect(row, findsOneWidget);
      // the Dorm side places are gone from the main list but not the pantry
      expect(find.byKey(const ValueKey('place-21')), findsNothing);
    });

    testWidgets('is not listed in edit mode', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit groups'));
      await tester.pumpAndSettle();
      expect(row, findsNothing);
    });

    testWidgets('has a label, a hint and a 48pt target, and opens the RIT page externally', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Free food pantry, Open until 7 PM · Hours may change' &&
              w.properties.hint == 'FoodShare, opens RIT page externally' &&
              w.properties.button == true,
        ),
        findsOneWidget,
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      await tester.tap(row);
      await tester.pump();
      expect(launcher.opened, [foodShareSourceUrl]);
      expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
    });

    testWidgets('copies the link when nothing can open it', (tester) async {
      UrlLauncherPlatform.instance = _Launcher(succeeds: false);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      await tester.tap(row);
      await tester.pump();
      await tester.pump();
      expect(copied, foodShareSourceUrl);
      expect(find.text('FoodShare copied'), findsOneWidget);
    });

    testWidgets('shows a keyboard focus ring', (tester) async {
      RitClock.pin(open);
      await pumpDiningScreen(tester);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      var shown = false;
      for (var i = 0; i < 40 && !shown; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        shown = find.byKey(const ValueKey('focus-ring')).evaluate().isNotEmpty;
      }
      expect(shown, isTrue);
      // it is on the FoodShare group, not some other control
      final ring = tester.getRect(find.byKey(const ValueKey('focus-ring')));
      expect(ring.overlaps(tester.getRect(row)), isTrue);
    });

    for (final size in const [Size(390, 1800), Size(440, 1800)]) {
      for (final brightness in Brightness.values) {
        for (final scale in const [1.0, 2.0]) {
          final name = 'dining_foodshare_${size.width.toInt()}_${brightness.name}_${scale.toInt()}x.png';
          goldenWidgets(name, (tester) async {
            RitClock.pin(open);
            await pumpDiningScreen(tester, size: size, brightness: brightness, scale: scale);
            await showAll(tester);
            expect(tester.takeException(), isNull);
            expect(row, findsOneWidget);
            // the whole row is on screen and at least 48 tall at this text size
            expect(tester.getRect(row).bottom, lessThanOrEqualTo(size.height));
            expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
            expect(tester.getRect(row).right, lessThanOrEqualTo(size.width));
            await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/$name'));
          });
        }
      }
    }
  });
}
