/// Pinned and Hidden sections, and how groups drop out when emptied.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/dining_layout.dart';
import 'package:tigerhub/data/dining_sections.dart';
import 'package:tigerhub/data/static_config.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/app_theme.dart';

import 'support/dining_harness.dart';

DiningSections _build({List<String> pinned = const [], Set<String> hidden = const {}, bool showHidden = true, DiningLayout layout = DiningLayout.empty, List<DiningLocation>? places}) {
  final config = StaticConfig.instance;
  return buildDiningSections(
    locations: places ?? sampleDining,
    layout: layout,
    defaults: config.diningGroups,
    defaultGroupOf: config.diningGroupFor,
    pinned: pinned,
    hidden: hidden,
    showHidden: showHidden,
  );
}

List<String> _names(Iterable<DiningLocation> l) => [for (final p in l) p.name];

void main() {
  setUpDining();

  group('sections', () {
    test('groups follow the default order and Other is last', () {
      final s = _build();
      expect([for (final g in s.groups) g.group.name], ['Dorm side', 'Student Alumni Union', 'Global Village', 'RIT Inn', 'Other']);
    });

    test('a pinned place shows only in Pinned', () {
      final s = _build(pinned: ['21']);
      expect(_names(s.pinned), ["Gracie's"]);
      expect(s.groups.expand((g) => g.places).map((l) => l.id), isNot(contains(21)));
    });

    test('Pinned lists open first, then the pin order', () {
      final s = _build(pinned: ['31', '32', '21']);
      expect(_names(s.pinned), ["Ben and Jerry's", "Gracie's", 'Beanz']);
    });

    test('inside a group open places come first', () {
      final s = _build();
      final dorm = s.groups.first.places;
      expect(_names(dorm), ["Gracie's", 'Beanz']);
      expect(dorm.map((l) => l.isOpen), [true, false]);
    });

    test('a hidden place leaves its group, and an emptied group loses its header', () {
      final s = _build(hidden: {'461'});
      expect(_names(s.hidden), ['Petals']);
      expect([for (final g in s.groups) g.group.name], isNot(contains('RIT Inn')));
    });

    test('Other has no header when empty', () {
      final s = _build(places: [place(21, "Gracie's")]);
      expect([for (final g in s.groups) g.group.name], ['Dorm side']);
    });

    test('showHidden off drops the Hidden list', () {
      expect(_build(hidden: {'21'}, showHidden: false).hidden, isEmpty);
    });
  });

  group('prefs', () {
    test('pinning a hidden place unhides it, hiding a pinned place unpins it', () async {
      final prefs = Preferences.instance;
      await prefs.toggleHidden(21);
      await prefs.togglePinned(21);
      expect(prefs.isHidden(21), isFalse);
      expect(prefs.isPinned(21), isTrue);
      await prefs.toggleHidden(21);
      expect(prefs.isPinned(21), isFalse);
      expect(prefs.isHidden(21), isTrue);
    });
  });

  group('screen', () {
    testWidgets('Pinned comes first and Hidden (N) is collapsed at the bottom', (tester) async {
      await Preferences.instance.togglePinned(32);
      await Preferences.instance.toggleHidden(481);
      await pumpDiningScreen(tester);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Dorm side'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      expect(find.text('Hidden (1)'), findsOneWidget);
      expect(find.text('Bytes'), findsNothing);
      expect(tester.getTopLeft(find.text('Pinned')).dy, lessThan(tester.getTopLeft(find.text('Dorm side')).dy));
      expect(tester.getTopLeft(find.text('Hidden (1)')).dy, greaterThan(tester.getTopLeft(find.text('Petals')).dy));
      await tester.tap(find.text('Hidden (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Bytes'), findsOneWidget);
    });

    testWidgets('Open now leaves hidden places out', (tester) async {
      await Preferences.instance.toggleHidden(21);
      await pumpDiningScreen(tester);
      // the default view is Open now, which has no Hidden section
      expect(find.textContaining('Hidden'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden (1)'), findsOneWidget);
      await tester.tap(find.text('Open now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hidden'), findsNothing);
      expect(find.text("Gracie's"), findsNothing);
    });
  });

  testWidgets('the Today card leaves hidden places out', (tester) async {
    await Preferences.instance.toggleHidden(21);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(body: SingleChildScrollView(child: DiningCard(result: Result(value: Collection(data: sampleDining, stale: false), state: DataState.ok)))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining("Gracie"), findsNothing);
    expect(find.text("Ben and Jerry's"), findsOneWidget);
  });

  testWidgets('group edits do not move the Today card', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    Future<List<String>> order() async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: Scaffold(body: SingleChildScrollView(child: DiningCard(result: Result(value: Collection(data: sampleDining, stale: false), state: DataState.ok)))),
      ));
      await tester.pumpAndSettle();
      final names = ["Gracie's", "Ben and Jerry's", 'Crossroads', 'Petals'];
      final seen = [for (final n in names) if (find.text(n).evaluate().isNotEmpty) n];
      seen.sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy));
      return seen;
    }

    final before = await order();
    final defaults = StaticConfig.instance.diningGroups;
    await Preferences.instance.setDiningLayout(DiningLayout.empty.moveGroup('global_village', -1, defaults).move(21, 'golisano', defaultGroup: 'dorm_side'));
    expect(await order(), before);
  });
}
