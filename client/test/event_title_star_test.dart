import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/cards/events_card.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/event_details_sheet.dart';

final _star = RegExp(r'[★☆✦-✹⭐]');

CampusEvent _event(String title) => CampusEvent(
  uid: 'u',
  source: 'test',
  title: title,
  startsAt: DateTime.utc(2026, 10, 9, 18),
);

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.from(ColorScheme.fromSeed(seedColor: Colors.orange)),
  home: Scaffold(body: child),
);

void main() {
  test('displayTitle drops leading stars and keeps the rest', () {
    expect(_event('✦ Trivia night').displayTitle, 'Trivia night');
    expect(_event('★ Trivia night').displayTitle, 'Trivia night');
    expect(_event('⭐ Trivia night').displayTitle, 'Trivia night');
    expect(_event('✨ Trivia night').displayTitle, 'Trivia night');
    expect(_event('Trivia ✦ night').displayTitle, 'Trivia ✦ night');
  });

  testWidgets('boosted row shows the plain title', (tester) async {
    await tester.pumpWidget(
      _wrap(EventRow(event: _event('Trivia night'), boosted: true)),
    );

    expect(find.text('Trivia night'), findsOneWidget);
    expect(find.textContaining(_star), findsNothing);
  });

  testWidgets('a star inside the feed title is not rendered or announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(EventRow(event: _event('✦ Trivia night'), boosted: true)),
    );

    expect(find.text('Trivia night'), findsOneWidget);
    expect(find.textContaining(_star), findsNothing);
    final labels = <String>[];
    void walk(SemanticsNode node) {
      labels.add(node.label);
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(EventRow)));
    expect(labels.any((l) => l.contains('Trivia night')), isTrue);
    expect(labels.any(_star.hasMatch), isFalse);
    handle.dispose();
  });

  test('share text starts without a star', () {
    final text = eventShareText(_event('✦ Trivia night'), 'Friday');
    expect(text.split('\n').first, 'Trivia night');
  });

  test('up next still lets a boosted event win a start-time tie', () {
    final a = _event('Alpha');
    final b = CampusEvent(
      uid: 'b',
      source: 'test',
      title: '✦ Zulu',
      startsAt: a.startsAt,
    );
    final order = upNextOrder(
      [a, b],
      boosted: {'b'},
      now: a.startsAt.subtract(const Duration(hours: 1)),
    );
    expect(order.first.uid, 'b');
  });
}
