/// With nothing cached a card shows its skeleton in place, then its content.
/// Never both in one frame.
///
/// Its own file because the response cache is a process wide singleton: any
/// other test that loads data first would leave something cached here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/freshness.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('priming shows the skeleton, then content, never both',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);

    final backend = _GatedBackend();
    await tester.pumpWidget(MaterialApp(
      home: AppShell(api: ApiClient(backend: backend), scheme: scheme),
    ));
    await tester.pump();

    expect(find.byType(PrimingPlaceholder), findsWidgets,
        reason: 'no skeleton in place while nothing is cached');

    backend.gate.complete();
    var sawContent = false;
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));

      // Each card holds exactly one of its two states per frame.
      for (final card in find.byType(CardShell).evaluate()) {
        final states = find.descendant(
          of: find.byWidget(card.widget),
          matching: find.byWidgetPredicate(
            (w) => w is KeyedSubtree && w.key is ValueKey<bool>,
          ),
        );
        expect(states.evaluate().length, lessThanOrEqualTo(1),
            reason: 'two states of one card in frame $frame');
      }

      if (find.byType(PrimingPlaceholder).evaluate().isEmpty) {
        sawContent = true;
      } else {
        expect(sawContent, isFalse,
            reason: 'skeleton came back after content at frame $frame');
      }
    }
    expect(sawContent, isTrue, reason: 'content never replaced the skeleton');
  });
}
