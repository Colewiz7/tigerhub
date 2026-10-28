/// Today ends with one Edit Today button. Move, resize and remove exist only
/// in edit mode, and the disclaimer lives in About, not on Today.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/config.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {'data': <dynamic>[], 'stale': false, 'last_updated': null};

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(value: Collection<T>(data: data, stale: false), state: DataState.ok);

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  Future<void> pumpToday(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 4000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
      home: Scaffold(
        body: HomeScreen(
          api: ApiClient(backend: _EmptyBackend()),
          dining: _ok(const [DiningLocation(id: 1, name: 'Crossroads', isOpen: true)]),
          events: _ok<CampusEvent>(const []),
          chefs: _ok<MenuItem>(const []),
          areas: _ok<HousingArea>(const []),
          onRefresh: () async {},
          onGoToTab: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the page ends with one centered Edit Today button', (tester) async {
    await pumpToday(tester);
    expect(find.text('Customize'), findsNothing);
    final button = tester.getRect(find.ancestor(of: find.text('Edit Today'), matching: find.byType(Material)).first);
    expect(button.center.dx, closeTo(195, 1));
    expect(find.text('Add module'), findsNothing);
  });

  testWidgets('the disclaimer is not on Today', (tester) async {
    await pumpToday(tester);
    expect(find.text(AppConfig.disclaimer), findsNothing);
  });

  testWidgets('move, inspect and remove appear only in edit mode', (tester) async {
    await pumpToday(tester);
    Iterable<String> actions() => [
      for (final widget in tester.widgetList<Semantics>(find.byType(Semantics)))
        for (final action in widget.properties.customSemanticsActions?.keys ?? const <CustomSemanticsAction>[])
          ?action.label,
    ];
    expect(find.byTooltip('Remove card from Today'), findsNothing);
    expect(find.byTooltip('Customize card'), findsNothing);
    expect(actions(), isNot(contains('Move down')));

    await tester.tap(find.text('Edit Today'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Add module'), findsOneWidget);
    expect(find.byTooltip('Remove card from Today'), findsWidgets);
    expect(actions(), contains('Move down'));
  });
}
