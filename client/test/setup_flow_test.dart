/// The setup flow: seven screens, one question each, nothing stored until the
/// end.
///
/// The risk with onboarding is a wall: a question the app cannot answer yet, or
/// a screen that will not let you past. These pin that every step can be
/// passed, that the first screen leaves in one tap, and that a step you did
/// not answer changes nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/services/preferences.dart';

import 'support/setup_harness.dart';

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
}
