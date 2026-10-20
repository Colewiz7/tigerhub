/// A tab switch is instant: one screen on stage, nothing fading, no overlay,
/// and nothing in a hidden tab can take focus.
///
/// Reported from a device: switching Events to Dining showed both screens at
/// partial opacity and a dim with a spinner over loaded content.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/screens/events_screen.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/services/preferences.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/arc_progress.dart';
import 'package:tigerhub/home_screen.dart';

const _categories = 4;
const _perCategory = 6;

/// Several dining groups of several rows, plus menu items and events, so the
/// tabs hold real lists. Answers can be held back with [gate].
class _DataBackend implements Backend {
  Completer<void>? gate;

  static String name(int id) => 'Place number $id';

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    await gate?.future;
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    final List<Map<String, dynamic>> data;
    switch (path) {
      case '/dining':
        data = [
          for (var c = 0; c < _categories; c++)
            for (var i = 0; i < _perCategory; i++)
              {
                'id': c * 100 + i,
                'name': name(c * 100 + i),
                'category': 'cat$c',
                'category_name': 'Category $c',
                'category_order': c,
                'is_open': i.isEven,
                'today': <dynamic>[],
              },
        ];
      case '/dining/specials':
        data = [
          for (var i = 0; i < 5; i++)
            {
              'id': i,
              'location_name': name(i),
              'name': 'Menu item $i',
              'category': 'Soup',
            },
        ];
      case '/events':
        final now = DateTime.now().toIso8601String();
        data = [
          for (var i = 0; i < 8; i++)
            {
              'uid': 'e$i',
              'source': 'test',
              'title': 'Event number $i',
              'starts_at': now,
            },
        ];
      default:
        data = [];
    }
    return {'data': data, 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

const _tabTypes = <String, Type>{
  'TODAY': HomeScreen,
  'DINING': DiningScreen,
  'EVENTS': EventsScreen,
  'MAP': MapScreen,
  'CAMPUS': CampusScreen,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<_DataBackend> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);

    final backend = _DataBackend();
    await tester.pumpWidget(MaterialApp(
      home: AppShell(api: ApiClient(backend: backend), scheme: scheme),
    ));
    await tester.pumpAndSettle();
    return backend;
  }

  void expectNoBlocker(String where) {
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'spinner $where');
    expect(find.byType(ModalBarrier).evaluate().where((e) {
      final barrier = e.widget as ModalBarrier;
      return barrier.color != null && barrier.color != Colors.transparent;
    }), isEmpty, reason: 'dimming barrier $where');
    expect(find.byType(ArcProgress), findsNothing, reason: 'arc spinner $where');
  }

  Finder diningSearch() => find.descendant(
        of: find.byType(DiningScreen, skipOffstage: false),
        matching: find.byType(TextField, skipOffstage: false),
        skipOffstage: false,
      );

  /// The one scrollable of the Dining body.
  ScrollPosition diningScroll(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
            of: find.descendant(
              of: find.byType(DiningScreen, skipOffstage: false),
              matching: find.byType(ListView, skipOffstage: false),
              skipOffstage: false,
            ),
            matching: find.byType(Scrollable, skipOffstage: false),
            skipOffstage: false,
          )
          .first)
      .position;

  testWidgets('one pump after a switch only the target tab is on stage',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('EVENTS'));
    await tester.pump();
    await tester.tap(find.text('DINING'));
    await tester.pump();

    expect(find.byType(DiningScreen), findsOneWidget);
    for (final type in [HomeScreen, EventsScreen, MapScreen, CampusScreen]) {
      expect(find.byType(type), findsNothing,
          reason: '$type is still painted one frame after the switch');
    }

    final fades = tester.widgetList<FadeTransition>(find.byType(FadeTransition));
    for (final fade in fades) {
      expect(fade.opacity.value, 1.0,
          reason: 'a screen is mid fade one frame after the switch');
    }
  });

  testWidgets('with data in hand no tab switch shows a blocker',
      (tester) async {
    await pumpShell(tester);

    for (final tab in ['DINING', 'EVENTS', 'MAP', 'CAMPUS', 'TODAY']) {
      await tester.tap(find.text(tab));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectNoBlocker('on $tab, frame $frame');
      }
      expect(find.byType(_tabTypes[tab]!), findsOneWidget);
    }
  });

  testWidgets('during an in flight refresh the cached content stays, unblocked',
      (tester) async {
    final backend = await pumpShell(tester);

    for (final tab in _tabTypes.keys) {
      await tester.tap(find.text(tab));
      await tester.pump();

      // The shell's two minute ticker asks again; the answer is held back.
      backend.gate = Completer<void>();
      await tester.pump(const Duration(minutes: 2));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectNoBlocker('refreshing $tab, frame $frame');
        if (tab == 'DINING') {
          expect(find.text(_DataBackend.name(0)), findsOneWidget,
              reason: 'Dining content went away mid refresh');
        }
        if (tab == 'EVENTS') {
          expect(find.text('Event number 0'), findsOneWidget,
              reason: 'Events content went away mid refresh');
        }
      }
      backend.gate!.complete();
      backend.gate = null;
      await tester.pumpAndSettle();
    }
  });

  testWidgets('dining filters and refresh never show two copies of the list',
      (tester) async {
    final backend = await pumpShell(tester);
    await Preferences.instance.togglePinned(1);
    await tester.tap(find.text('DINING'));
    await tester.pumpAndSettle();

    void expectOneList(String where) {
      expect(find.byType(ListView), findsOneWidget, reason: 'lists $where');
      expect(find.text('Today’s published menu'), findsOneWidget,
          reason: 'menu group $where');
      for (var id = 0; id < _perCategory; id++) {
        expect(find.text(_DataBackend.name(id)).evaluate().length,
            lessThanOrEqualTo(1),
            reason: 'row ${_DataBackend.name(id)} twice $where');
      }
    }

    Future<void> step(String where) async {
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectOneList('$where, frame $frame');
      }
    }

    expectOneList('at rest');
    for (final chip in ['Open', 'Open', 'Pinned (1)', 'Pinned (1)']) {
      await tester.tap(find.textContaining(chip).first);
      await step('after $chip');
    }

    await tester.enterText(diningSearch(), 'number 1');
    await step('after search');
    await tester.enterText(diningSearch(), '');
    await step('after clearing search');

    backend.gate = Completer<void>();
    await tester.pump(const Duration(minutes: 2));
    await step('during refresh');
    backend.gate!.complete();
    backend.gate = null;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expectOneList('after refresh, frame $frame');
    }
  });

  testWidgets('a hidden tab cannot hold focus or take keyboard input',
      (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('DINING'));
    await tester.pumpAndSettle();

    await tester.tap(diningSearch());
    await tester.pump();
    await tester.enterText(diningSearch(), 'abc');
    expect(tester.widget<TextField>(diningSearch()).focusNode!.hasFocus, isTrue);

    await tester.tap(find.text('EVENTS'));
    await tester.pump();

    final focus = FocusManager.instance.primaryFocus;
    expect(focus?.context?.findAncestorWidgetOfExactType<DiningScreen>(), isNull,
        reason: 'focus is still inside the hidden Dining tab');
    expect(tester.widget<TextField>(diningSearch()).focusNode!.hasFocus, isFalse,
        reason: 'the hidden search field kept focus');
    expect(tester.testTextInput.hasAnyClients, isFalse,
        reason: 'the hidden search field still receives text input');
  });

  testWidgets('switching back keeps a tab\'s state and scroll offset',
      (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('DINING'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Open').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final offset = diningScroll(tester).pixels;
    expect(offset, greaterThan(0), reason: 'the list did not scroll');

    await tester.tap(find.text('EVENTS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DINING'));
    await tester.pumpAndSettle();

    expect(diningScroll(tester).pixels, offset);
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Open'),
    );
    expect(chip.selected, isTrue, reason: 'the Open filter was reset');
  });
}
