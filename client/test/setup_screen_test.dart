/// First run setup.
///
/// The risk with an onboarding screen is that it becomes a wall: something that
/// asks a question the app cannot answer yet, or that will not let you past.
/// These tests pin the properties that stop that happening, chiefly that
/// skipping works and that the question is never asked twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/setup_screen.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real zones, from docs/notes.md 7.9. RIT Inn bypasses the campus post
  // offices entirely, which the screen has to say rather than ask for a room.
  final areas = [
    const HousingArea(
      id: 'residence-halls',
      name: 'Residence Halls',
      line2Example: 'Peterson 1234',
    ),
    const HousingArea(
      id: 'global-village',
      name: 'Global Village',
      line2Example: 'GV 400 1020',
    ),
    const HousingArea(
      id: 'rit-inn',
      name: 'RIT Inn',
      directDelivery: true,
    ),
  ];

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await Preferences.instance.clearHome();
    await Preferences.instance.load();
  });

  Future<int> pump(WidgetTester tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: SetupScreen(areas: areas, onDone: () => done++),
    ));
    await tester.pumpAndSettle();
    return done;
  }

  testWidgets('offers every housing zone', (tester) async {
    await pump(tester);
    for (final area in areas) {
      expect(find.text(area.name), findsOneWidget);
    }
  });

  testWidgets('cannot save without picking somewhere', (tester) async {
    await pump(tester);
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull,
        reason: 'saving nothing would store a blank home and never ask again');
  });

  testWidgets('asks for a room only once a zone is picked', (tester) async {
    await pump(tester);
    // The hint is per zone, so the field is meaningless before then.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Residence Halls'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Peterson 1234'), findsOneWidget,
        reason: "the hint shows that zone's documented format");
  });

  testWidgets('does not ask a direct delivery zone for a room', (tester) async {
    await pump(tester);

    await tester.tap(find.text('RIT Inn'));
    await tester.pumpAndSettle();

    // Mail goes to the property, so there is no building and room to give.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('straight to the property'), findsOneWidget);
  });

  testWidgets('saving stores the zone and the room', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Global Village'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'GV 400 1020');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(Preferences.instance.homeArea, 'global-village');
    expect(Preferences.instance.homeUnit, 'GV 400 1020');
    expect(Preferences.instance.setupSeen, isTrue);
  });

  testWidgets('skipping stores nothing but still counts as answered',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Residence Halls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Nothing invented on the way past.
    expect(Preferences.instance.homeArea, isNull);
    // But never asked again. An app that re-asks every launch is worse than
    // one that never asked.
    expect(Preferences.instance.setupSeen, isTrue);
  });

  testWidgets('reports done exactly once, whichever way out', (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(
        ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
      ),
      home: SetupScreen(areas: areas, onDone: () => done++),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('a room typed then abandoned is not saved', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Residence Halls'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Peterson 9999');
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(Preferences.instance.homeUnit, '');
  });
}
