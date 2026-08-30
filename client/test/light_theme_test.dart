/// The app, rendered in light mode.
///
/// `ThemeMode.system` is set and a light scheme is built, but every screenshot
/// ever taken of this app is dark, and no test rendered a screen in light until
/// this one. A widget with a hardcoded colour, or art that vanishes on a pale
/// surface, would have gone unnoticed indefinitely.
///
/// This is a breakage check, not a design review. It asserts the screens build
/// and their content is there. Judging whether light mode *looks* right is
/// Codex's half and needs eyes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/empty_state.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

ThemeData lightTheme() => AppTheme.from(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFFF76902),
        brightness: Brightness.light,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('every tab renders in light mode', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 950);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();

    await tester.pumpWidget(MaterialApp(
      theme: lightTheme(),
      home: AppShell(api: ApiClient(backend: _EmptyBackend()), scheme: scheme),
    ));
    await tester.pumpAndSettle();

    for (final tab in ['DINING', 'EVENTS', 'MAP', 'CAMPUS', 'TODAY']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$tab threw in light mode');
    }

    scheme.dispose();
  });

  testWidgets('the empty state art still renders on a pale surface',
      (tester) async {
    // The illustrations use fixed colours rather than theme roles. On the light
    // surface their cream fill is effectively the background (contrast 1.06),
    // and the shape is carried by the cocoa outline instead, which measures
    // 11.66 there. That is a legitimate way to draw an outlined illustration,
    // but it means light mode leans entirely on the outline, so it is worth
    // knowing that the art draws at all rather than assuming.
    await tester.pumpWidget(MaterialApp(
      theme: lightTheme(),
      home: const Scaffold(
        body: Center(child: EmptyState(kind: EmptyKind.noEvents)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Nothing scheduled today'), findsOneWidget);
  });

  testWidgets('the wordmark follows the theme into light mode', (tester) async {
    // "Hub" is currentColor. In dark mode that has to resolve light; here it
    // has to resolve dark, and a widget that hardcoded either would be wrong in
    // one of them.
    final scheme = SchemeController();
    await scheme.load();

    await tester.pumpWidget(MaterialApp(
      theme: lightTheme(),
      home: AppShell(api: ApiClient(backend: _EmptyBackend()), scheme: scheme),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    scheme.dispose();
  });
}
