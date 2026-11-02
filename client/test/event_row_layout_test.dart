/// The standard event row stacks its text: title, then time, then place.
/// Nothing sits beside the title, so nothing cuts it short.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/theme/app_theme.dart';

CampusEvent _event({
  String title = 'Gather & Game Hangout (For Deaf and Hard of Hearing Students)',
  String? location = 'SLT Community Room, Student Life Center',
  DateTime? startsAt,
  bool allDay = false,
}) => CampusEvent(
  uid: 'u',
  source: 'test',
  title: title,
  location: location,
  startsAt: startsAt ?? CampusTime.wall(2026, 11, 3, 12),
  allDay: allDay,
);

Future<void> _pump(WidgetTester tester, CampusEvent event, {double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 800);
  addTearDown(tester.view.reset);
  RitClock.pin(CampusTime.wall(2026, 11, 2, 10, 34));
  addTearDown(RitClock.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 800), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: EventRow(event: event, stacked: true))),
      ),
    ),
  );
}

void main() {
  testWidgets('time sits under the title, not beside it', (tester) async {
    await _pump(tester, _event());
    final title = find.textContaining('Gather & Game');
    final stamp = find.textContaining('Tue 3 Nov, noon');
    expect(stamp, findsOneWidget);
    expect(tester.getTopLeft(stamp).dx, tester.getTopLeft(title).dx);
    expect(tester.getTopLeft(stamp).dy, greaterThan(tester.getBottomLeft(title).dy - 1));
  });

  testWidgets('a long title takes two lines and is cut only after that', (tester) async {
    await _pump(tester, _event());
    final title = tester.widget<Text>(find.textContaining('Gather & Game'));
    expect(title.maxLines, 2);
    final box = tester.renderObject<RenderParagraph>(find.textContaining('Gather & Game'));
    expect(box.size.width, greaterThan(200));
  });

  testWidgets('title uses the full lane, with no time column beside it', (tester) async {
    await _pump(tester, _event());
    final title = tester.getRect(find.textContaining('Gather & Game'));
    final row = tester.getRect(find.byType(EventRow));
    // badge 42 + gap 13 + padding 12 each side
    expect(row.right - title.right, lessThanOrEqualTo(12 + 1));
  });

  testWidgets('today names its day like every other row', (tester) async {
    await _pump(tester, _event(startsAt: CampusTime.wall(2026, 11, 2, 13)));
    expect(find.textContaining('Mon 2 Nov, 1:00 PM'), findsOneWidget);
  });

  testWidgets('all day events name the day', (tester) async {
    await _pump(tester, _event(allDay: true));
    expect(find.textContaining('Tue 3 Nov, all day'), findsOneWidget);
  });

  testWidgets('the place is not cut to one line at large text', (tester) async {
    await _pump(tester, _event(), scale: 1.5);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('SLT Community Room'), findsOneWidget);
  });
}
