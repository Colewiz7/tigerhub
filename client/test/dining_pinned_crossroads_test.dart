/// Dining: a pinned, open Crossroads is listed under Pinned, the last row
/// clears the floating tab bar, and rows leave the top edge softly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/dining_layout.dart';
import 'package:tigerhub/data/dining_sections.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/jump_list.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

import 'support/dining_harness.dart';

void main() {
  setUpDining();

  test('a pinned and open Crossroads shows under Pinned beside another pin', () {
    final config = StaticConfig.instance;
    final s = buildDiningSections(
      locations: sampleDining,
      layout: DiningLayout.empty,
      defaults: config.diningGroups,
      defaultGroupOf: config.diningGroupFor,
      pinned: const ['21', '23'],
      hidden: const {},
    );
    expect([for (final p in s.pinned) p.id], [21, 23]);
    expect(s.groups.expand((g) => g.places).map((l) => l.id), isNot(contains(23)));
  });

  Future<void> pump(WidgetTester tester, {double inset = 0}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(
          body: TabBarInset(
            bottom: inset,
            child: DiningScreen(
              api: ApiClient(backend: EmptyBackend()),
              result: Result(value: Collection(data: sampleDining, stale: false), state: DataState.ok),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('scrolled to the end, the last row sits above the tab bar', (tester) async {
    await Preferences.instance.togglePinned(23);
    await pump(tester, inset: 87);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(JumpList), matching: find.byType(Scrollable)).first;
    await tester.drag(list, const Offset(0, -5000));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text('Petals'));
    expect(last.bottom, lessThanOrEqualTo(700 - 87));
  });

  testWidgets('the list has a soft top edge once rows scroll out under the chips', (tester) async {
    // a tall inset makes the short sample list scroll
    await pump(tester, inset: 400);
    BoxDecoration fade() => tester
        .widget<DecoratedBox>(find.byKey(const ValueKey('jump-list-top-fade')))
        .decoration as BoxDecoration;
    expect(fade().gradient, isNull);
    await tester.drag(find.descendant(of: find.byType(JumpList), matching: find.byType(Scrollable)).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(fade().gradient, isNotNull);
  });
}
