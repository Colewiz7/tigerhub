/// Setup inside the app: who sees the flow, who sees the one-time sheet, and
/// how a re-run from Settings reaches Today.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/screens/settings/settings_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/dashboard.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/today_header.dart';

import 'support/setup_harness.dart';

class _Backend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    if (path == '/housing/areas') {
      return {
        'data': [
          {'id': 'residence-halls', 'name': 'Residence Halls', 'line2_example': 'Peterson 1234', 'post_office': 'dsp'},
          {'id': 'global-village', 'name': 'Global Village', 'line2_example': 'GV 400 1020', 'post_office': 'global-village'},
        ],
        'stale': false,
        'last_updated': null,
      };
    }
    if (path.endsWith('/address')) throw Exception('no address in this test');
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSetupStorage);
  tearDown(Preferences.instance.resetForTests);

  Future<SchemeController> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(api: ApiClient(backend: _Backend()), scheme: scheme)));
    await tester.pumpAndSettle();
    return scheme;
  }

  group('a fresh install', () {
    testWidgets('goes straight into the flow', (tester) async {
      await pumpShell(tester);
      expect(find.text('Welcome to TigerHub'), findsOneWidget);
      expect(find.text("What's new in TigerHub"), findsNothing);
    });

    testWidgets('Use defaults enters the app and is never asked again', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('Use defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHeader), findsOneWidget);
      expect(Preferences.instance.setupSeen, isTrue);
    });

    testWidgets('finishing the flow lands on Today', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mocha'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
      }
      expect(find.text("You're all set"), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHeader), findsOneWidget);
      expect(Preferences.instance.setupSeen, isTrue);
    });
  });

  group('someone who already has settings', () {
    Future<void> seed() async {
      await Preferences.instance.setHome(area: 'global-village');
      await Preferences.instance.load();
    }

    testWidgets('is not backfilled, and gets the sheet instead of the flow', (tester) async {
      await seed();
      await pumpShell(tester);
      expect(find.text('Welcome to TigerHub'), findsNothing);
      expect(find.text("What's new in TigerHub"), findsOneWidget);
      expect(find.text('Personalize'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      // the sheet does not mark anything until it is answered
    });

    testWidgets('Not now answers it for good', (tester) async {
      await seed();
      await pumpShell(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text("What's new in TigerHub"), findsNothing);
      expect(Preferences.instance.setupSeen, isTrue);
      expect(find.byType(TodayHeader), findsOneWidget);
    });

    testWidgets('a dismissal is not an answer and the sheet comes back', (tester) async {
      await seed();
      await pumpShell(tester);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.text("What's new in TigerHub"), findsNothing);
      expect(Preferences.instance.setupSeen, isFalse);

      // the next launch builds the shell again
      await tester.pumpWidget(const SizedBox());
      Preferences.instance.resetForTests();
      await pumpShell(tester);
      expect(find.text("What's new in TigerHub"), findsOneWidget);
    });

    testWidgets('the back button dismisses without answering', (tester) async {
      await seed();
      await pumpShell(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("What's new in TigerHub"), findsNothing);
      expect(Preferences.instance.setupSeen, isFalse);
    });

    testWidgets('Personalize opens the re-run, filled in, with Cancel and Save', (tester) async {
      await seed();
      await pumpShell(tester);
      await tester.tap(find.text('Personalize'));
      await tester.pumpAndSettle();
      expect(Preferences.instance.setupSeen, isTrue);
      expect(find.text('Pick a look'), findsOneWidget);
      expect(find.text('Welcome to TigerHub'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHeader), findsOneWidget);
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Open settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('Personalize TigerHub is the first row', (tester) async {
      await Preferences.instance.markSetupSeen();
      await pumpShell(tester);
      await openSettings(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      final personalize = tester.getTopLeft(find.text('Personalize TigerHub')).dy;
      expect(personalize, lessThan(tester.getTopLeft(find.text('Today').last).dy));
      expect(personalize, lessThan(tester.getTopLeft(find.text('Appearance')).dy));
    });

    testWidgets('the row reruns setup and Save changes Today', (tester) async {
      await Preferences.instance.markSetupSeen();
      await pumpShell(tester);
      await openSettings(tester);
      await tester.tap(find.text('Personalize TigerHub'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a look'), findsOneWidget);

      // to Your Today, switch Calendar on, then Save
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('Calendar').last, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = await DashboardStore.load();
      expect(saved.where((c) => c.type == ModuleType.calendar && !c.hidden), hasLength(1));
      // Today was already loaded, and picked the change up
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Edit Today'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Calendar'), findsWidgets);
    });
  });
}
