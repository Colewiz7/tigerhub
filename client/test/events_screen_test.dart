import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/events_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/event_details_sheet.dart';

void main() {
  setUp(Preferences.instance.resetForTests);

  Future<void> pumpEvents(
    WidgetTester tester, {
    Size size = const Size(900, 800),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final today = CampusTime.dateOf(CampusTime.nowUtc());
    final events = [
      CampusEvent(
        uid: 'today',
        source: 'campusgroups',
        title: 'Jazz concert',
        startsAt: DateTime(today.year, today.month, today.day, 18),
        endsAt: DateTime(today.year, today.month, today.day, 20),
        description: '<p>Live jazz &amp; refreshments.</p>\n---\nEvent Details: https://events.test/jazz',
        organizer: 'Music Program',
        organizerKey: 'MUSIC',
        location: 'Ingle Auditorium',
        eventType: 'Performance',
        url: 'https://events.test/jazz',
      ),
      CampusEvent(
        uid: 'tomorrow',
        source: 'campusgroups',
        title: 'Robotics game night',
        startsAt: DateTime(today.year, today.month, today.day + 1, 18),
        organizer: 'Robotics Club',
        organizerKey: 'ROBOTICS',
        location: 'SHED',
        eventType: 'Social',
      ),
      CampusEvent(
        uid: 'hidden-workshop',
        source: 'campusgroups',
        title: 'Career workshop',
        startsAt: DateTime(today.year, today.month, today.day, 16),
        organizer: 'Career Services',
        organizerKey: 'CAREER',
        location: 'Bausch and Lomb Center',
        eventType: 'Workshop',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(
          ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
        ),
        home: Scaffold(
          body: EventsScreen(
            result: Result(
              value: Collection(data: events, stale: false),
              state: DataState.ok,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('search matches title, organizer, type, and location', (
    tester,
  ) async {
    await pumpEvents(tester);
    await tester.enterText(find.byType(TextField), 'SHED');
    await tester.pumpAndSettle();

    expect(find.textContaining('Robotics game night'), findsOneWidget);
    expect(find.text('Jazz concert'), findsNothing);
    expect(find.text('1 event'), findsOneWidget);
  });

  testWidgets('explicit search reveals a default keyword-hidden event', (
    tester,
  ) async {
    await pumpEvents(tester);
    expect(find.text('Career workshop'), findsNothing);

    await tester.enterText(find.byType(TextField), 'workshop');
    await tester.pumpAndSettle();

    expect(find.text('Career workshop'), findsOneWidget);
    expect(find.text('1 event'), findsOneWidget);
  });

  testWidgets('today excludes future events without changing preferences', (
    tester,
  ) async {
    await pumpEvents(tester);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(find.text('Jazz concert'), findsOneWidget);
    expect(find.textContaining('Robotics game night'), findsNothing);
  });

  testWidgets('event controls fit a phone width and control F focuses search', (
    tester,
  ) async {
    await pumpEvents(tester, size: const Size(360, 700));
    expect(tester.takeException(), isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
  });

  test('event descriptions strip markup and duplicate source links', () {
    expect(
      eventDescriptionText(
        '<p>Bring food &amp; friends&#33;</p>\n---\nEvent Details: https://x.test',
        eventUrl: 'https://x.test',
      ),
      'Bring food & friends!',
    );
  });

  testWidgets('tapping an event opens full details and copies its link', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpEvents(tester);
    await tester.tap(find.text('Jazz concert'));
    await tester.pumpAndSettle();

    expect(find.text('Live jazz & refreshments.'), findsOneWidget);
    expect(find.text('Ingle Auditorium'), findsWidgets);
    expect(find.text('Copy event link'), findsOneWidget);

    await tester.tap(find.text('Copy event link'));
    await tester.pump();
    expect(copied, 'https://events.test/jazz');

    await tester.tap(find.text('Copy event details'));
    await tester.pump();
    expect(copied, contains('Jazz concert'));
    expect(copied, contains('Ingle Auditorium'));
    expect(copied, contains('https://events.test/jazz'));
  });
}
