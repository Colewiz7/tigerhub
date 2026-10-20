/// A tab switch is instant: one screen on stage, nothing fading, no overlay.
///
/// Reported from a device: switching Events to Dining showed both screens at
/// partial opacity, a dim with a spinner over loaded content, and two copies
/// of the Dining list at once.
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
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/arc_progress.dart';
import 'package:tigerhub/widgets/freshness.dart';
import 'package:tigerhub/home_screen.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

/// Holds every answer until released, so the shell sits in its priming state.
class _GatedBackend implements Backend {
  final gate = Completer<void>();

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    await gate.future;
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
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

  Future<SchemeController> pumpShell(
    WidgetTester tester,
    Backend backend, {
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);

    await tester.pumpWidget(MaterialApp(
      home: AppShell(api: ApiClient(backend: backend), scheme: scheme),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return scheme;
  }

  void expectNoBlocker(WidgetTester tester, String where) {
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'spinner $where');
    expect(find.byType(ModalBarrier).evaluate().where((e) {
      final barrier = e.widget as ModalBarrier;
      return barrier.color != null && barrier.color != Colors.transparent;
    }), isEmpty, reason: 'dimming barrier $where');
    expect(find.byType(ArcProgress), findsNothing, reason: 'arc spinner $where');
  }

  testWidgets('one pump after a switch only the target tab is on stage',
      (tester) async {
    await pumpShell(tester, _EmptyBackend());

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
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'an animation is still running after the switch');
  });

  testWidgets('with data in hand no tab switch shows a blocker',
      (tester) async {
    await pumpShell(tester, _EmptyBackend());

    for (final tab in ['DINING', 'EVENTS', 'MAP', 'CAMPUS', 'TODAY']) {
      await tester.tap(find.text(tab));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectNoBlocker(tester, 'on $tab, frame $frame');
      }
      expect(find.byType(_tabTypes[tab]!), findsOneWidget);
    }
  });

  testWidgets('a refresh with data in hand shows no blocker', (tester) async {
    await pumpShell(tester, _EmptyBackend());

    for (final tab in _tabTypes.keys) {
      await tester.tap(find.text(tab));
      await tester.pump();
      // The shell's two minute ticker asks again while the tab is open.
      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expectNoBlocker(tester, 'refreshing $tab');
    }
  });

  testWidgets('priming shows the skeleton, then content, never both',
      (tester) async {
    final backend = _GatedBackend();
    await pumpShell(tester, backend, settle: false);

    expect(find.byType(PrimingPlaceholder), findsWidgets,
        reason: 'no skeleton in place while nothing is cached');

    backend.gate.complete();
    var sawContent = false;
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final skeletons = find.byType(PrimingPlaceholder).evaluate().length;
      final empties = find.text('No events').evaluate().length +
          find.text('No dining').evaluate().length;
      if (skeletons == 0) sawContent = true;
      if (sawContent) {
        expect(skeletons, 0, reason: 'skeleton came back at frame $frame');
      }
      // A card swaps its skeleton for content in place. One child, not two.
      for (final switcher in find.byType(AnimatedSwitcher).evaluate()) {
        final states = find.descendant(
          of: find.byWidget(switcher.widget),
          matching: find.byWidgetPredicate(
            (w) => w is KeyedSubtree && w.key is ValueKey<bool>,
          ),
        );
        expect(states.evaluate().length, lessThanOrEqualTo(1),
            reason: 'two states of one card in frame $frame ($empties)');
      }
    }
    expect(sawContent, isTrue);
  });

  testWidgets('dining filters never show two copies of the list',
      (tester) async {
    await pumpShell(tester, _EmptyBackend());
    await tester.tap(find.text('DINING'));
    await tester.pump();

    for (final chip in ['Open', 'Open']) {
      await tester.tap(find.text(chip));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(ListView), findsOneWidget,
            reason: 'two lists in frame $frame after toggling $chip');
        expect(find.text('Today’s published menu'), findsOneWidget);
      }
    }
  });
}
