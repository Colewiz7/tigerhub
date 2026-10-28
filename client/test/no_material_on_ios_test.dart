/// No Material glyph shows on iOS outside AppIconKind.materialOnIos.
///
/// Two checks. The source scan keeps every icon in lib going through
/// AppIconKind. The render walk drives the real app on iOS and inspects every
/// Icon it builds, which also catches glyphs a framework widget picks for
/// itself, like a back button or a dropdown arrow.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/sources/campus_places.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

final _rawIcon = RegExp(r'(?<![A-Za-z])Icons\.\w|CupertinoIcons\.\w|IconData\(');

List<String> rawIconLines(String source) => [
  for (final (i, line) in source.split('\n').indexed)
    if (_rawIcon.hasMatch(line)) '${i + 1}: ${line.trim()}',
];

final _allowed = {for (final kind in AppIconKind.materialOnIos) kind.cupertino};

List<String> materialGlyphs(WidgetTester tester) => [
  for (final icon in tester.widgetList<Icon>(find.byType(Icon, skipOffstage: false)))
    if (icon.icon != null && icon.icon!.fontFamily != 'CupertinoIcons' && !_allowed.contains(icon.icon))
      'U+${icon.icon!.codePoint.toRadixString(16)} (${icon.icon!.fontFamily})',
];

class _Backend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    final now = DateTime.now().toIso8601String();
    final data = switch (path) {
      '/dining' => [
        for (var i = 0; i < 3; i++)
          {'id': i, 'name': 'Place $i', 'category': 'cat', 'category_name': 'Category', 'category_order': 0, 'is_open': true, 'today': <dynamic>[]},
      ],
      '/events' => [
        for (var i = 0; i < 3; i++)
          {'uid': 'e$i', 'source': 'test', 'title': 'Event $i', 'starts_at': now, 'url': 'https://example.edu/e$i', 'location': 'Room $i'},
      ],
      '/campus/map' => parseCampusMapFeatures(File('test/fixtures/maps_category_35.data').readAsStringSync()),
      _ => <dynamic>[],
    };
    return {'data': data, 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  test('lib names icons only through AppIconKind', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('widgets/app_icon.dart')) continue;
      for (final line in rawIconLines(file.readAsStringSync())) {
        offenders.add('${file.path}:$line');
      }
    }
    expect(offenders, isEmpty, reason: 'use an AppIconKind so iOS gets Cupertino:\n${offenders.join('\n')}');
  });

  test('the scan would catch a raw icon', () {
    expect(rawIconLines('icon: Icon(Icons.close_rounded),'), hasLength(1));
    expect(rawIconLines('icon: Icon(CupertinoIcons.xmark),'), hasLength(1));
    expect(rawIconLines('icon: Icon(AppIconKind.close.of(context)),'), isEmpty);
  });

  testWidgets('the render check would catch a framework default', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DropdownButton<int>(value: 1, items: const [DropdownMenuItem(value: 1, child: Text('One'))], onChanged: (_) {})),
    ));
    expect(materialGlyphs(tester), isNotEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  group('the app on iOS', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    });

    testWidgets('draws no Material glyph outside the exceptions', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final scheme = SchemeController();
      await scheme.load();
      addTearDown(scheme.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(SchemeController.builtIn(Brightness.light)),
        home: AppShell(api: ApiClient(backend: _Backend()), scheme: scheme),
      ));
      await tester.pumpAndSettle();

      void check(String where) => expect(materialGlyphs(tester), isEmpty, reason: where);
      Finder tab(String label) => find.descendant(of: find.byType(AppTabBar), matching: find.text(label));

      check('today');
      await tester.scrollUntilVisible(find.text('Customize'), 300, scrollable: find.byType(Scrollable).first);
      // built in the cache extent is not on screen
      await tester.ensureVisible(find.text('Customize'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customize'));
      await tester.pumpAndSettle();
      check('today, customizing');
      // back to the top, clear of the short date bar
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pumpAndSettle();
      final diningOptions = find.descendant(
        of: find.ancestor(of: find.text('Eat now'), matching: find.byType(CardShell)),
        matching: find.byTooltip('Customize card'),
      );
      await tester.tap(diningOptions.first);
      await tester.pumpAndSettle();
      // the dining card's options carry a dropdown, the arrow is a framework default
      await tester.scrollUntilVisible(find.byType(DropdownButtonFormField<String>), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      check('card options');
      await tester.scrollUntilVisible(find.text('Add module'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Add module'));
      await tester.pumpAndSettle();
      check('card library');
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();

      for (final label in ['Dining', 'Events', 'Map', 'Campus']) {
        await tester.tap(tab(label));
        await tester.pumpAndSettle();
        check(label);
        // the sheets and views each tab opens
        final opener = switch (label) {
          'Dining' => find.text('Place 0').hitTestable(),
          'Events' => find.text('Event 0').hitTestable(),
          'Map' => find.byTooltip('Search campus places (Ctrl+F)'),
          _ => null,
        };
        if (opener == null) continue;
        expect(opener, findsWidgets, reason: '$label has nothing to open');
        await tester.tap(opener.first);
        await tester.pumpAndSettle();
        check('$label, opened');
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }

      // a pushed section brings the app bar back button
      await tester.tap(find.text('Safety'));
      await tester.pumpAndSettle();
      check('campus safety');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // the gear lives on today
      await tester.tap(tab('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Open settings'));
      await tester.pumpAndSettle();
      check('settings');
      for (final section in ['Appearance', 'About']) {
        await tester.tap(find.text(section).last);
        await tester.pumpAndSettle();
        check('settings $section');
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
