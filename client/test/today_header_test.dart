/// Today heads itself: the round mark and the gear, then today's date as a
/// large title. Settings has its own large title and Close. No palette lock.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/screens/settings/settings_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/large_title.dart';
import 'package:tigerhub/widgets/today_header.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Preferences.instance.resetForTests();
  });
  tearDown(() {
    RitClock.reset();
    Preferences.instance.resetForTests();
  });

  Future<SchemeController> pumpShell(WidgetTester tester, {double width = 390, double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);
    await Preferences.instance.markSetupSeen();
    await tester.pumpWidget(MaterialApp(home: AppShell(api: ApiClient(backend: _EmptyBackend()), scheme: scheme)));
    await tester.pumpAndSettle();
    return scheme;
  }

  Finder title(String text) => find.widgetWithText(LargeTitle, text);

  testWidgets('the date title is the campus date and turns over at campus midnight', (tester) async {
    // 11:59 PM tue sep 29 on campus is 3:59 AM utc wed
    RitClock.pin(CampusTime.wall(2026, 9, 29, 23, 59));
    await pumpShell(tester);
    expect(title('Tuesday, September 29'), findsOneWidget);

    RitClock.pin(CampusTime.wall(2026, 9, 30, 0, 0, 30));
    await tester.pump(const Duration(minutes: 1));
    expect(title('Wednesday, September 30'), findsOneWidget);
  });

  testWidgets('the long date wraps at 2x text and is never cut', (tester) async {
    RitClock.pin(CampusTime.wall(2026, 9, 30, 12));
    await pumpShell(tester, scale: 2);
    final text = find.descendant(of: title('Wednesday, September 30'), matching: find.byType(Text));
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(text).width, lessThanOrEqualTo(390 - 32));
  });

  testWidgets('scrolled past the title, a short date bar keeps the gear', (tester) async {
    RitClock.pin(CampusTime.wall(2026, 9, 30, 12));
    await pumpShell(tester);
    expect(find.byType(TodayCollapsedBar), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byType(TodayCollapsedBar), findsOneWidget);
    expect(find.text('Wed, Sep 30'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(TodayCollapsedBar), matching: find.byTooltip('Settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the mark is a round 32 with no wordmark beside it', (tester) async {
    await pumpShell(tester);
    final mark = find.descendant(of: find.byType(TodayHeader), matching: find.byType(ClipOval));
    expect(tester.getSize(mark), const Size(32, 32));
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Wordmark'), findsNothing);
  });

  testWidgets('Settings has a large title and Close returns to Today', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.bySemanticsLabel('Open settings'));
    await tester.pumpAndSettle();
    expect(title('Settings'), findsOneWidget);
    expect(find.byType(TodayHeader), findsNothing);

    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(TodayHeader), findsOneWidget);
  });

  testWidgets('there is no palette lock in the shell', (tester) async {
    await pumpShell(tester);
    expect(find.bySemanticsLabel(RegExp('color palette|wallpaper colors')), findsNothing);
  });
}
