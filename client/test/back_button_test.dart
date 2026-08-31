/// Android's back button.
///
/// Without handling, back exits the app from wherever you are. Every real
/// Android app walks back to its home tab first, and losing the whole app
/// because you wanted to leave Settings is a jarring way to lose your place.
///
/// Driven through the shell rather than by calling a handler, because the
/// thing worth guarding is that the app does not close.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
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

  Future<SchemeController> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 950);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(api: ApiClient(backend: _EmptyBackend()), scheme: scheme),
      ),
    );
    await tester.pumpAndSettle();
    return scheme;
  }

  testWidgets('back on another tab returns to Today, it does not exit',
      (tester) async {
    final scheme = await pump(tester);

    await tester.tap(find.text('CAMPUS'));
    await tester.pumpAndSettle();

    // The route must refuse to pop, which is what keeps the app open.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isTrue, reason: 'the shell handled it rather than exiting');

    // Handling it is not the same as landing on Today. A second back is what
    // proves where the first one went: at home there is nothing left to
    // absorb, so the route lets it through.
    final second = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(second, isFalse, reason: 'the first back should have reached Today');
    expect(tester.takeException(), isNull);

    scheme.dispose();
  });

  testWidgets('back on Today lets the app close', (tester) async {
    // The home tab is where back should mean what it normally means.
    final scheme = await pump(tester);

    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isFalse, reason: 'nothing left to go back to');
    expect(tester.takeException(), isNull);

    scheme.dispose();
  });
}
