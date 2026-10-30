/// The setup flow: seven screens, one question each, nothing stored until the
/// end.
///
/// The risk with onboarding is a wall: a question the app cannot answer yet, or
/// a screen that will not let you past. These pin that every step can be
/// passed, that the first screen leaves in one tap, and that a step you did
/// not answer changes nothing.
library;

import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/screens/setup/setup_kit.dart' show SetupGroup;
import 'package:tigerhub/services/cache.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';

import 'support/setup_harness.dart';

// the one capsule button, whatever it says
Future<void> advance(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

// the previews scroll sideways, so the one to tap is brought into view first
Future<void> tapLook(WidgetTester tester, AppScheme scheme) async {
  await tester.ensureVisible(find.text(scheme.label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(scheme.label));
  await tester.pumpAndSettle();
}

// the Today picture repeats the card names, so rows are found inside the list
Finder inList(String label) => find.descendant(of: find.byType(SetupGroup), matching: find.text(label));

// lists build lazily, so what is below the fold needs a scroll first
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

// from the welcome screen, a number of steps on
Future<SetupHarness> openAt(WidgetTester tester, int steps, {Size size = const Size(390, 844), double scale = 1}) async {
  final harness = await pumpSetup(tester, size: size, scale: scale);
  for (var i = 0; i < steps; i++) {
    await advance(tester);
  }
  return harness;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSetupStorage);
  tearDown(Preferences.instance.resetForTests);

  group('welcome', () {
    testWidgets('names the app, lists three things, and offers two ways on', (tester) async {
      await pumpSetup(tester);
      expect(find.text('Welcome to TigerHub'), findsOneWidget);
      expect(find.text("What's open to eat"), findsOneWidget);
      expect(find.text("Events you'll care about"), findsOneWidget);
      expect(find.text('Campus at a glance'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Use defaults'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('Use defaults marks setup answered, changes nothing and leaves once', (tester) async {
      final harness = await pumpSetup(tester);
      await tester.tap(find.text('Use defaults'));
      await tester.pumpAndSettle();
      expect(harness.done, 1);
      expect(Preferences.instance.setupSeen, isTrue);
      expect(Preferences.instance.homeArea, isNull);
      expect(Preferences.instance.pinnedDining, isEmpty);
    });

    testWidgets('has no back chevron and no step dots', (tester) async {
      await pumpSetup(tester);
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('pick a look', () {
    Future<SetupHarness> open(WidgetTester tester) async {
      final harness = await pumpSetup(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('shows a preview for every scheme and no Skip', (tester) async {
      await open(tester);
      expect(find.text('Pick a look'), findsOneWidget);
      for (final scheme in AppScheme.values) {
        expect(find.text(scheme.label), findsOneWidget);
      }
      expect(find.text('Skip'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('says Set up later until something is chosen, then Continue', (tester) async {
      await open(tester);
      expect(find.text('Set up later'), findsOneWidget);
      await tapLook(tester, AppScheme.slate);
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Set up later'), findsNothing);
    });

    testWidgets('a pick recolours the setup live', (tester) async {
      final harness = await open(tester);
      final before = Theme.of(tester.element(find.text('Pick a look'))).colorScheme.surface;
      await tapLook(tester, AppScheme.slate);
      await tester.pumpAndSettle();
      expect(harness.scheme.choice, AppScheme.slate);
      final after = Theme.of(tester.element(find.text('Pick a look'))).colorScheme.surface;
      expect(after, isNot(before));
      expect(after, SchemeController.forChoice(AppScheme.slate).surface);
    });

    testWidgets('Reduce Motion crossfades the push instead of sliding', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpSetup(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final route = ModalRoute.of(tester.element(find.text('Pick a look')));
      expect(route, isA<PageRouteBuilder<void>>());
      await tester.pumpAndSettle();
      expect(find.text('Pick a look'), findsOneWidget);
    });

    testWidgets('on iOS the push is the native Cupertino route', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpSetup(tester);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(ModalRoute.of(tester.element(find.text('Pick a look'))), isA<CupertinoPageRoute<void>>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the chosen preview is the checked radio', (tester) async {
      // below: semantics
      final handle = tester.ensureSemantics();
      await open(tester);
      await tapLook(tester, AppScheme.mocha);
      await tester.pumpAndSettle();
      final data = tester.getSemantics(find.bySemanticsLabel(AppScheme.mocha.label)).getSemanticsData();
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
      final other = tester.getSemantics(find.bySemanticsLabel(AppScheme.espresso.label)).getSemanticsData();
      expect(other.flagsCollection.isChecked, CheckedState.isFalse);
      handle.dispose();
    });
  });

  group('where you live', () {
    testWidgets('lists every area and asks for no room until one is chosen', (tester) async {
      await openAt(tester, 2);
      expect(find.text('Where you live'), findsOneWidget);
      expect(find.text('For your mailing address and shuttle times.'), findsOneWidget);
      for (final area in setupAreas) {
        expect(find.text(area.name), findsOneWidget);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Set up later'), findsOneWidget);
    });

    testWidgets('a checkmark marks the chosen area and the room field follows', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('Residence Halls'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Peterson 1234'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      final row = find.ancestor(of: find.text('Residence Halls'), matching: find.byType(Row)).first;
      final check = find.byWidgetPredicate((w) => w is AppIcon && w.kind == AppIconKind.check);
      expect(find.descendant(of: row, matching: check), findsOneWidget);
      final other = find.ancestor(of: find.text('Global Village'), matching: find.byType(Row)).first;
      expect(find.descendant(of: other, matching: check), findsNothing);
    });

    testWidgets('never opens the keyboard on its own', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('Residence Halls'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNull);
    });

    testWidgets('a tap outside drops the keyboard', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('Residence Halls'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNotNull);
      await tester.tapAt(const Offset(200, 120));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNull);
    });

    testWidgets('a direct delivery area has no room field', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('RIT Inn'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('straight to the property'), findsOneWidget);
    });

    testWidgets('the answer is held in the draft, nothing is stored yet', (tester) async {
      final harness = await openAt(tester, 2);
      await tester.tap(find.text('Global Village'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'GV 400 1020');
      expect(Preferences.instance.homeArea, isNull);
      expect(harness.done, 0);
      await advance(tester);
      expect(Preferences.instance.homeArea, isNull);
    });

    testWidgets('no areas says Housing unavailable and still moves on', (tester) async {
      await pumpSetup(tester, areas: const []);
      await advance(tester);
      await advance(tester);
      expect(find.text('Housing unavailable'), findsOneWidget);
      expect(find.text('Set up later'), findsOneWidget);
      await advance(tester);
      expect(find.text('Your spots'), findsOneWidget);
    });
  });

  group('your spots', () {
    testWidgets('groups the places under the current Dining headers', (tester) async {
      await openAt(tester, 3);
      expect(find.text('Your spots'), findsOneWidget);
      expect(find.text('Dorm side'), findsOneWidget);
      expect(find.text("Gracie's"), findsOneWidget);
      await reveal(tester, find.text('Global Village'));
      expect(find.text('Crossroads'), findsOneWidget);
      expect(find.text('The Cafe & Market at Crossroads'), findsNothing);
      await reveal(tester, find.text('Other'));
      expect(find.text('Bytes'), findsOneWidget);
    });

    testWidgets('follows a renamed group', (tester) async {
      final prefs = Preferences.instance;
      await prefs.setDiningLayout(prefs.diningLayout.rename('dorm_side', 'West side', defaultName: 'Dorm side'));
      await openAt(tester, 3);
      expect(find.text('West side'), findsOneWidget);
      expect(find.text('Dorm side'), findsNothing);
    });

    testWidgets('a tap picks a place with a check badge and changes the button', (tester) async {
      final harness = await openAt(tester, 3);
      expect(find.text('Set up later'), findsOneWidget);
      await tester.tap(find.text("Gracie's"));
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      final check = find.byWidgetPredicate((w) => w is AppIcon && w.kind == AppIconKind.check);
      expect(check, findsOneWidget);
      // held in the draft, nothing stored
      expect(Preferences.instance.pinnedDining, isEmpty);
      expect(harness.done, 0);
      await tester.tap(find.text("Gracie's"));
      await tester.pumpAndSettle();
      expect(check, findsNothing);
      expect(find.text('Set up later'), findsOneWidget);
    });

    testWidgets('the Hide Dorm side switch is on top, off, and names its four places', (tester) async {
      await openAt(tester, 3);
      expect(find.text('Hide Dorm side'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text("Gracie's, Beanz, The Commons, The College Grind"), findsOneWidget);
      final switchTop = tester.getTopLeft(find.byType(Switch)).dy;
      expect(switchTop, lessThan(tester.getTopLeft(find.text("Gracie's")).dy));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Continue'), findsOneWidget);
      expect(Preferences.instance.hiddenDiningGroups, isEmpty);
    });

    testWidgets('an empty Dining says so and Set up later still works', (tester) async {
      await pumpSetup(tester, dining: const []);
      for (var i = 0; i < 3; i++) {
        await advance(tester);
      }
      expect(find.text('Dining unavailable'), findsOneWidget);
      expect(find.text('Set up later'), findsOneWidget);
      await advance(tester);
      expect(find.text('Pick what your events list favors.'), findsOneWidget);
    });

    testWidgets('every tile is a 48 point target', (tester) async {
      await openAt(tester, 3);
      for (final name in ["Gracie's", 'Bytes']) {
        if (name == 'Bytes') await reveal(tester, find.text(name));
        final tile = find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;
        final size = tester.getSize(tile);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    for (final (size, scale) in [(const Size(390, 844), 2.0), (const Size(440, 956), 2.0), (const Size(390, 844), 1.0)]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} at ${scale}x text, button pinned', (tester) async {
        await openAt(tester, 3, size: size, scale: scale);
        expect(tester.takeException(), isNull);
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.bottom, lessThanOrEqualTo(size.height));
        expect(button.height, greaterThanOrEqualTo(50));
        expect(button.left, 20);
        expect(button.right, size.width - 20);
        // the short name is reachable and whole at large text
        await reveal(tester, find.text('Crossroads'));
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byType(FilledButton)), button);
      });
    }
  });

  group('events', () {
    testWidgets('offers the four presets as radio cards, none chosen', (tester) async {
      await openAt(tester, 4);
      expect(find.text('Events'), findsOneWidget);
      for (final name in ['Free and fun', 'Academic and career', 'Low key', 'Everything']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Set up later'), findsOneWidget);
    });

    testWidgets('picking one fills its radio and the button says Continue', (tester) async {
      await openAt(tester, 4);
      await tester.tap(find.text('Low key'));
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      final check = find.byWidgetPredicate((w) => w is AppIcon && w.kind == AppIconKind.check);
      expect(check, findsOneWidget);
      // not stored, the rules are the shipped ones
      expect(Preferences.instance.hideKeywords, defaultHideKeywords);
    });

    testWidgets('Follow a club has a chevron and pushes a search', (tester) async {
      await openAt(tester, 4);
      final row = find.ancestor(of: find.text('Follow a club'), matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.byWidgetPredicate((w) => w is AppIcon && w.kind == AppIconKind.chevron)), findsOneWidget);
      await tester.tap(find.text('Follow a club'));
      await tester.pumpAndSettle();
      expect(find.text('Search clubs'), findsOneWidget);
      expect(find.text('Chess Club'), findsOneWidget);
      expect(find.text('Student Government'), findsOneWidget);
    });

    testWidgets('the search narrows by name and following shows on the step', (tester) async {
      await openAt(tester, 4);
      await tester.tap(find.text('Follow a club'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'chess');
      await tester.pumpAndSettle();
      expect(find.text('Student Government'), findsNothing);
      await tester.tap(find.text('Chess Club'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('1 followed'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('a search with no hits says No matches', (tester) async {
      await openAt(tester, 4);
      await tester.tap(find.text('Follow a club'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('no events says so, the row is off and Set up later works', (tester) async {
      await pumpSetup(tester, events: const []);
      for (var i = 0; i < 4; i++) {
        await advance(tester);
      }
      expect(find.text('Events unavailable'), findsOneWidget);
      await tester.tap(find.text('Follow a club'));
      await tester.pumpAndSettle();
      expect(find.text('Search clubs'), findsNothing);
      expect(find.text('Set up later'), findsOneWidget);
      await advance(tester);
      expect(find.text('Your Today'), findsWidgets);
    });

    testWidgets('fits a phone at twice the text', (tester) async {
      await openAt(tester, 4, scale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(FilledButton)).bottom, lessThanOrEqualTo(844));
      await reveal(tester, find.text('Follow a club'));
      expect(tester.takeException(), isNull);
    });
  });

  group('your Today', () {
    bool isOn(WidgetTester tester, String label) {
      final row = find.ancestor(of: inList(label), matching: find.byType(Row)).first;
      return tester.widget<Switch>(find.descendant(of: row, matching: find.byType(Switch))).value;
    }

    testWidgets('lists the library with a preview, and leaves Facility hours out', (tester) async {
      await openAt(tester, 5);
      expect(find.text('Your Today'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-preview')), findsOneWidget);
      await reveal(tester, inList('Mailing address'));
      for (final label in ['Eat now', 'Up next', 'Calendar', 'Visiting chefs', 'Academic dates', 'Campus map', 'Shuttles', 'Package pickup']) {
        expect(inList(label), findsOneWidget);
      }
      expect(find.text('Facility hours'), findsNothing);
    });

    testWidgets('starts from the default cards', (tester) async {
      await openAt(tester, 5);
      expect(isOn(tester, 'Eat now'), isTrue);
      expect(isOn(tester, 'Up next'), isTrue);
      expect(isOn(tester, 'Calendar'), isFalse);
      expect(isOn(tester, 'Shuttles'), isFalse);
    });

    testWidgets('a home turns Shuttles and Package pickup on, a followed club adds a row', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('Global Village'));
      await tester.pumpAndSettle();
      await advance(tester);
      await advance(tester);
      await tester.tap(find.text('Follow a club'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chess Club'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await advance(tester);
      await reveal(tester, inList('Package pickup'));
      expect(isOn(tester, 'Shuttles'), isTrue);
      expect(isOn(tester, 'Package pickup'), isTrue);
      await reveal(tester, inList('Chess Club'));
      expect(isOn(tester, 'Chess Club'), isTrue);
    });

    testWidgets('a switch changes the preview', (tester) async {
      await openAt(tester, 5);
      final preview = find.byKey(const ValueKey('today-preview'));
      expect(find.descendant(of: preview, matching: find.text('Calendar')), findsNothing);
      await reveal(tester, inList('Calendar'));
      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();
      expect(isOn(tester, 'Calendar'), isTrue);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.descendant(of: preview, matching: find.text('Calendar')), findsOneWidget);
    });

    testWidgets('anything answered on the way earns the summary', (tester) async {
      final harness = await openAt(tester, 1);
      await tapLook(tester, AppScheme.slate);
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await advance(tester);
      }
      expect(find.text('Your Today'), findsWidgets);
      expect(find.text('Continue'), findsOneWidget);
      await advance(tester);
      expect(find.text("You're all set"), findsOneWidget);
      expect(harness.done, 0);
    });

    testWidgets('Set up later here ends the flow with nothing changed', (tester) async {
      final harness = await openAt(tester, 5);
      expect(find.text('Set up later'), findsOneWidget);
      await advance(tester);
      expect(harness.done, 1);
      expect(Preferences.instance.setupSeen, isTrue);
      expect(Preferences.instance.homeArea, isNull);
    });

    testWidgets('fits a phone at twice the text', (tester) async {
      await openAt(tester, 5, scale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(FilledButton)).bottom, lessThanOrEqualTo(844));
      await reveal(tester, inList('Mailing address'));
      expect(tester.takeException(), isNull);
    });
  });

  group('done and the whole flow', () {
    final haptics = <String>[];

    setUp(() {
      haptics.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    testWidgets('an untouched run is all defaults', (tester) async {
      final harness = await openAt(tester, 1);
      for (var i = 0; i < 5; i++) {
        await advance(tester);
      }
      // the last input step ends the flow when nothing was chosen
      expect(harness.done, 1);
    });

    testWidgets('a full run lands every answer and says so on the last screen', (tester) async {
      final harness = await openAt(tester, 1);
      await tapLook(tester, AppScheme.mocha);
      await tester.pumpAndSettle();
      await advance(tester);
      await tester.tap(find.text('Global Village'));
      await tester.pumpAndSettle();
      await advance(tester);
      await tester.tap(find.text("Gracie's"));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await advance(tester);
      await tester.tap(find.text('Everything'));
      await tester.pumpAndSettle();
      await advance(tester);
      await reveal(tester, inList('Calendar'));
      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();
      await advance(tester);

      expect(find.text("You're all set"), findsOneWidget);
      expect(find.text('Change any of this in Settings.'), findsOneWidget);
      expect(find.text('Mocha'), findsOneWidget);
      expect(find.text('Global Village'), findsOneWidget);
      expect(find.text('1 place, Dorm side hidden'), findsOneWidget);
      expect(find.text('Everything'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(harness.done, 0);
      expect(Preferences.instance.setupSeen, isFalse);

      await advance(tester);
      expect(harness.done, 1);
      final prefs = Preferences.instance;
      expect(prefs.homeArea, 'global-village');
      expect(prefs.pinnedDining, {'21'});
      expect(prefs.hiddenDiningGroups, {'dorm_side'});
      expect(prefs.keywordRulesEnabled, isFalse);
      expect(prefs.setupSeen, isTrue);
      expect(harness.scheme.choice, AppScheme.mocha);
    });

    testWidgets('only Get started gives the light impact, picks give a selection click', (tester) async {
      await openAt(tester, 1);
      await tapLook(tester, AppScheme.mocha);
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      haptics.clear();
      for (var i = 0; i < 5; i++) {
        await advance(tester);
      }
      expect(haptics, isEmpty);
    });

    testWidgets('Get started taps the light impact once', (tester) async {
      await openAt(tester, 1);
      await tapLook(tester, AppScheme.mocha);
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await advance(tester);
      }
      haptics.clear();
      await advance(tester);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('skipping Events keeps today\'s keyword defaults', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('Global Village'));
      await tester.pumpAndSettle();
      await advance(tester);
      await tester.tap(find.text("Gracie's"));
      await tester.pumpAndSettle();
      await advance(tester);
      // events untouched
      await advance(tester);
      await advance(tester);
      await advance(tester);
      expect(Preferences.instance.hideKeywords, defaultHideKeywords);
      expect(Preferences.instance.boostKeywords, defaultBoostKeywords);
      expect(Preferences.instance.keywordRulesEnabled, isTrue);
    });

    testWidgets('a home and spots show Shuttles and Package pickup on Today after Save', (tester) async {
      await openAt(tester, 2);
      await tester.tap(find.text('Global Village'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await advance(tester);
      }
      await advance(tester);
      await advance(tester);
      final cards = await DashboardStore.load();
      expect(cards.where((c) => !c.hidden).map((c) => c.type), containsAll([ModuleType.shuttles, ModuleType.packagePickup]));
    });

    for (final (size, scale) in [(const Size(390, 844), 1.0), (const Size(390, 844), 2.0), (const Size(440, 956), 1.0), (const Size(440, 956), 2.0)]) {
      testWidgets('every step fits ${size.width.toInt()}x${size.height.toInt()} at ${scale}x text', (tester) async {
        await openAt(tester, 0, size: size, scale: scale);
        for (var i = 0; i < 6; i++) {
          expect(tester.takeException(), isNull, reason: 'step $i');
          final button = tester.getRect(find.byType(FilledButton));
          expect(button.bottom, lessThanOrEqualTo(size.height), reason: 'step $i button on screen');
          expect(button.height, greaterThanOrEqualTo(50));
          if (i == 4) {
            await reveal(tester, find.text('Low key'));
            await tester.tap(find.text('Low key'));
            await tester.pumpAndSettle();
          }
          await advance(tester);
        }
        expect(find.text("You're all set"), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a re-run', () {
    final base = [
      ...defaultDashboard,
      const CardInstance(id: 'shuttles-0', type: ModuleType.shuttles, size: CardSize.compact),
    ];

    Future<SetupHarness> openRerun(WidgetTester tester, {AppScheme initial = AppScheme.mocha}) async {
      final prefs = Preferences.instance;
      await prefs.setHome(area: 'global-village', unit: 'GV 400 1020');
      await prefs.togglePinned(21);
      await prefs.applyProfile(['x'], ['y'], keywordsEnabled: true);
      await DashboardStore.save(base);
      return pumpSetup(tester, rerun: true, dashboard: base, initial: initial);
    }

    testWidgets('has no welcome, Cancel on the left and Save on the right', (tester) async {
      await openRerun(tester);
      expect(find.text('Welcome to TigerHub'), findsNothing);
      expect(find.text('Pick a look'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Cancel')).dx, lessThan(tester.getTopLeft(find.text('Save')).dx));
    });

    testWidgets('every step starts filled in from what is stored', (tester) async {
      final handle = tester.ensureSemantics();
      await openRerun(tester);
      expect(tester.getSemantics(find.bySemanticsLabel(AppScheme.mocha.label)).getSemanticsData().flagsCollection.isChecked, CheckedState.isTrue);
      await advance(tester);
      final row = find.ancestor(of: find.text('Global Village'), matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.byWidgetPredicate((w) => w is AppIcon && w.kind == AppIconKind.check)), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'GV 400 1020');
      await advance(tester);
      expect(tester.getSemantics(find.bySemanticsLabel("Gracie's")).getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('Cancel puts the scheme back and stores nothing', (tester) async {
      final harness = await openRerun(tester);
      await tapLook(tester, AppScheme.slate);
      await tester.pumpAndSettle();
      expect(harness.scheme.choice, AppScheme.slate);
      await advance(tester);
      await tester.tap(find.text('Residence Halls'));
      await tester.pumpAndSettle();
      // Cancel is only on the first step, so go back to it
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.scheme.choice, AppScheme.mocha);
      expect(harness.cancelled, 1);
      expect(Preferences.instance.homeArea, 'global-village');
    });

    testWidgets('the system back button cancels too', (tester) async {
      final harness = await openRerun(tester);
      await tapLook(tester, AppScheme.slate);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.scheme.choice, AppScheme.mocha);
      expect(harness.cancelled, 1);
    });

    testWidgets('Save with nothing edited leaves everything as it was', (tester) async {
      final harness = await openRerun(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(harness.done, 1);
      final prefs = Preferences.instance;
      expect(prefs.hideKeywords, ['x']);
      expect(prefs.pinnedDining, {'21'});
      expect(prefs.homeUnit, 'GV 400 1020');
      expect([for (final c in await DashboardStore.load()) c.toJson()], [for (final c in base) c.toJson()]);
    });

    testWidgets('turning a card off hides it, and its place, size and scope stay', (tester) async {
      await openRerun(tester);
      for (var i = 0; i < 4; i++) {
        await advance(tester);
      }
      await reveal(tester, inList('Shuttles'));
      await tester.tap(find.descendant(of: find.ancestor(of: inList('Shuttles'), matching: find.byType(Row)).first, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = await DashboardStore.load();
      expect(saved.length, base.length);
      final shuttles = saved.firstWhere((c) => c.id == 'shuttles-0');
      expect((shuttles.hidden, shuttles.size), (true, CardSize.compact));
      expect([for (final c in saved) c.id], [for (final c in base) c.id]);
    });

    testWidgets('the last screen says Save', (tester) async {
      await openRerun(tester);
      for (var i = 0; i < 5; i++) {
        await advance(tester);
      }
      expect(find.text("You're all set"), findsOneWidget);
      expect(find.text('Save'), findsWidgets);
      expect(find.text('Get started'), findsNothing);
    });
  });

  group('a tried look is only a preview', () {
    Future<List<String>> stored() => ResponseCache.instance.readOrder('color_scheme');

    Color surface(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.surface;

    testWidgets('back to Welcome and Use defaults leaves the stored look and the theme alone', (tester) async {
      final harness = await openAt(tester, 1);
      final original = surface(tester);
      await tapLook(tester, AppScheme.mocha);
      expect(surface(tester), isNot(original));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use defaults'));
      await tester.pumpAndSettle();
      expect(await stored(), isEmpty);
      expect(harness.scheme.choice, AppScheme.espresso);
      expect(surface(tester), original);
      expect(harness.done, 1);
    });

    testWidgets('the pick is saved when the flow is applied', (tester) async {
      final harness = await openAt(tester, 1);
      await tapLook(tester, AppScheme.mocha);
      expect(await stored(), isEmpty);
      for (var i = 0; i < 6; i++) {
        await advance(tester);
      }
      expect(harness.done, 1);
      expect(await stored(), [AppScheme.mocha.id]);
      expect(harness.scheme.choice, AppScheme.mocha);
    });

    testWidgets('a re-run Cancel restores the look and saves nothing', (tester) async {
      final harness = await pumpSetup(tester, rerun: true);
      await tapLook(tester, AppScheme.slate);
      expect(harness.scheme.choice, AppScheme.slate);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.scheme.choice, AppScheme.espresso);
      expect(await stored(), isEmpty);
    });

    testWidgets('leaving the flow without applying saves nothing and the theme returns', (tester) async {
      final harness = await openAt(tester, 1);
      await tapLook(tester, AppScheme.mocha);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(await stored(), isEmpty);
      expect(harness.scheme.choice, AppScheme.espresso);
      expect(harness.scheme.storedChoice, AppScheme.espresso);
    });

    testWidgets('the whole setup recolours as a look is tried', (tester) async {
      await openAt(tester, 1);
      final before = surface(tester);
      await tapLook(tester, AppScheme.slate);
      expect(surface(tester), SchemeController.forChoice(AppScheme.slate).surface);
      expect(surface(tester), isNot(before));
    });
  });
}
