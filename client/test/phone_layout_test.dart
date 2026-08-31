/// Every tab, at the width of a phone.
///
/// Android became a real target, and the whole point of it is checking dining
/// hours on a phone between classes. Nothing had ever rendered these screens
/// at that width: every existing widget test uses a desktop viewport, and the
/// responsive breakpoints drop to one column under 700, which is a layout path
/// that was effectively untested.
///
/// An overflow throws in a test but only paints a yellow stripe in release, so
/// this is the difference between finding it here and shipping it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/tab_bar.dart';

/// Enough real-shaped content that the screens actually build rows, chips and
/// control bars. An empty backend renders empty states, which is the one
/// layout that cannot overflow, so it proves nothing about a phone.
class _PopulatedBackend implements Backend {
  static const _longName = 'The Cafe and Market at Crossroads';

  List<Map<String, dynamic>> get _dining => [
    for (var i = 0; i < 12; i++)
      {
        'id': i,
        'name': i.isEven ? _longName : 'Gracie\'s',
        'is_open': i.isEven,
        'closes_at': '2026-08-31T21:00:00Z',
        'opens_at': '2026-08-31T10:30:00Z',
        'category_name': i < 6 ? 'Residence dining' : 'Retail and cafes',
        'category_order': i < 6 ? 1 : 2,
        'occupancy': i == 0
            ? {'count': 115, 'max_occ': 150, 'percent_full': 76}
            : null,
      },
  ];

  List<Map<String, dynamic>> get _events => [
    for (var i = 0; i < 12; i++)
      {
        'uid': 'e$i',
        'source': i.isEven ? 'campusgroups' : 'drupal',
        'title': 'Weekly Erev Shabbat Service with fellowship afterward $i',
        'starts_at': '2026-08-31T18:00:00Z',
        'organizer': 'RIT FoodShare and Friends of the Library',
        'organizer_key': 'foodshare',
        'location': 'Student Alumni Union, Fireside Lounge',
      },
  ];

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    List<dynamic> data = const [];
    if (path == '/dining') data = _dining;
    if (path == '/events') data = _events;
    if (path == '/dining/visiting-chefs') {
      data = [
        for (var i = 0; i < 4; i++)
          {'id': i, 'name': 'Chef Alexandria Fontaine', 'location_name': _longName},
      ];
    }
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': data, 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  // A Pixel-class phone in logical pixels. Narrower than any breakpoint the
  // layout has, so this is the one-column path throughout.
  const phone = Size(411, 914);

  Future<List<String>> sweepTabs(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = phone;
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: AppShell(
            api: ApiClient(backend: _PopulatedBackend()),
            scheme: scheme,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final broken = <String>[];
    for (final tab in ['TODAY', 'DINING', 'EVENTS', 'MAP', 'CAMPUS']) {
      // Scoped to the tab strip: a populated Today grid renders its own
      // "TODAY" text in a card footer, so a bare text finder is ambiguous.
      await tester.tap(
        find.descendant(of: find.byType(AppTabBar), matching: find.text(tab)),
      );
      await tester.pumpAndSettle();
      final failure = tester.takeException();
      if (failure != null) broken.add('$tab: $failure');
    }
    scheme.dispose();
    return broken;
  }

  testWidgets('every tab survives the larger system font sizes',
      (tester) async {
    // A phone held by someone who has turned text up is still a phone that has
    // to work, and text scaling is the usual way a layout that fits at 1.0
    // stops fitting. 2.0 is past Android's largest display setting and well
    // into the accessibility range.
    //
    // This found three real faults at 1.3 and above: every StatusRow spilled
    // its fixed 72px box, the scalloped badge pushed its number outside the
    // scallop, and the loading skeleton outgrew the card it stands in for.
    expect(await sweepTabs(tester, textScale: 2.0), isEmpty);
  });

  testWidgets('every tab lays out on a phone without overflowing',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = phone;
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(backend: _PopulatedBackend()), scheme: scheme),
      ),
    );
    await tester.pumpAndSettle();

    final broken = <String>[];
    for (final tab in ['TODAY', 'DINING', 'EVENTS', 'MAP', 'CAMPUS']) {
      // Scoped to the tab strip: a populated Today grid renders its own
      // "TODAY" text in a card footer, so a bare text finder is ambiguous.
      await tester.tap(
        find.descendant(
          of: find.byType(AppTabBar),
          matching: find.text(tab),
        ),
      );
      await tester.pumpAndSettle();
      final failure = tester.takeException();
      if (failure != null) broken.add('$tab: $failure');
    }

    expect(broken, isEmpty, reason: broken.join('\n'));
    scheme.dispose();
  });
}
