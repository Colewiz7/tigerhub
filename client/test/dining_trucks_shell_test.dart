/// Dining re-reads its trucks when the real shell activates it, ticks or resumes.
///
/// Its own file because the response cache is a process wide singleton.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/data/campus_time.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

class _Backend implements Backend {
  int truckReads = 0;

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    if (path == '/dining/food-trucks') {
      truckReads++;
      return {
        'data': <dynamic>[],
        'stale': false,
        'last_updated': CampusTime.format(DateTime.now().toUtc()),
        'availability': 'unavailable',
      };
    }
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Future<_Backend> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);

    final backend = _Backend();
    await tester.pumpWidget(MaterialApp(
      home: AppShell(api: ApiClient(backend: backend), scheme: scheme),
    ));
    await tester.pumpAndSettle();
    return backend;
  }

  Future<void> go(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  testWidgets('switching Today to Dining re-reads the trucks', (tester) async {
    final backend = await pumpShell(tester);
    final before = backend.truckReads;
    expect(before, greaterThan(0));

    await go(tester, 'DINING');

    expect(backend.truckReads, greaterThan(before));
  });

  testWidgets('switching Events to Dining re-reads, switching away does not', (tester) async {
    final backend = await pumpShell(tester);

    await go(tester, 'EVENTS');
    final onEvents = backend.truckReads;
    await go(tester, 'DINING');

    expect(backend.truckReads, greaterThan(onEvents));

    final onDining = backend.truckReads;
    await go(tester, 'EVENTS');

    expect(backend.truckReads, onDining);
  });

  testWidgets('staying on Dining does not re-read', (tester) async {
    final backend = await pumpShell(tester);
    await go(tester, 'DINING');
    final reads = backend.truckReads;

    await go(tester, 'DINING');
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(backend.truckReads, reads);
  });

  testWidgets("the shell's two minute tick re-reads, on Dining and behind another tab", (tester) async {
    final backend = await pumpShell(tester);

    await go(tester, 'DINING');
    var reads = backend.truckReads;
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(backend.truckReads, greaterThan(reads), reason: 'on Dining');

    await go(tester, 'EVENTS');
    reads = backend.truckReads;
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(backend.truckReads, greaterThan(reads), reason: 'behind Events');
  });

  testWidgets('resuming the app re-reads', (tester) async {
    final backend = await pumpShell(tester);
    await go(tester, 'DINING');

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    final reads = backend.truckReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(backend.truckReads, greaterThan(reads));
  });
}
