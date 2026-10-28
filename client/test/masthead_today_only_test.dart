/// The mark and gear sit on Today only. Dining, Events and Campus get a plain
/// large title, and Map gets nothing above it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/large_title.dart';

import 'support/tabs.dart';

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
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Finder mark() => find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.contains('mascot'));

  testWidgets('the mark is on Today and on no other tab', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);

    await tester.pumpWidget(MaterialApp(home: AppShell(api: ApiClient(backend: _EmptyBackend()), scheme: scheme)));
    await tester.pumpAndSettle();
    expect(mark(), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    for (final (tab, titled) in [('Dining', true), ('Events', true), ('Map', false), ('Campus', true)]) {
      await tester.tap(tabLabel(tab));
      await tester.pumpAndSettle();
      expect(mark(), findsNothing, reason: tab);
      expect(find.byTooltip('Settings'), findsNothing, reason: tab);
      expect(find.widgetWithText(LargeTitle, tab), titled ? findsOneWidget : findsNothing, reason: tab);
    }

    await tester.tap(tabLabel('Today'));
    await tester.pumpAndSettle();
    expect(mark(), findsOneWidget);
  });
}
