/// Row menus on the dashboard are off in Customize mode, where long-press is a
/// drag. Outside it they open from long-press, right-click and the menu key.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/event_row.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/widgets/context_actions.dart';

import 'support/context_menu_harness.dart';

class _EmptyBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? q,
  ]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    return {'data': <dynamic>[], 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

Result<Collection<T>> _ok<T>(List<T> data) => Result(
  value: Collection<T>(data: data, stale: false),
  state: DataState.ok,
);

final _events = _ok([
  CampusEvent(
    uid: 'e0',
    source: 'test',
    title: 'Robotics Meeting',
    startsAt: DateTime.utc(2099, 1, 1, 15),
    organizer: 'Robotics Club',
    organizerKey: 'robotics club',
  ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 844) * 3;
    addTearDown(tester.view.reset);
    MenuProbe().install(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: menuTheme(),
        home: Scaffold(
          body: HomeScreen(
            api: ApiClient(backend: _EmptyBackend()),
            dining: _ok<DiningLocation>(const []),
            events: _events,
            chefs: _ok<MenuItem>(const []),
            areas: _ok<HousingArea>(const []),
            onRefresh: () async {},
            onGoToTab: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toggleCustomize(WidgetTester tester) async {
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Customize').evaluate().isEmpty
          ? find.text('Done')
          : find.text('Customize'),
    );
    await tester.pumpAndSettle();
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  Finder row() => find.byType(EventRow).first;

  // inside the row's ContextActions, which the keyboard helper needs
  Finder title() =>
      find.descendant(of: row(), matching: find.text('Robotics Meeting'));

  Set<String> semanticsActionLabels(WidgetTester tester) {
    final node = tester.getSemantics(
      find
          .descendant(of: row(), matching: find.byType(ContextActions))
          .first,
    );
    return {
      for (final id in node.getSemanticsData().customSemanticsActionIds ?? [])
        CustomSemanticsAction.getAction(id)!.label!,
    };
  }

  testWidgets('outside edit mode the row opens a menu three ways', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester);
    expect(row(), findsOneWidget);

    await longPress(tester, title());
    expect(menuItems, findsWidgets, reason: 'long-press');
    await tester.tapAt(const Offset(2, 2));
    await expectMenuClosed(tester);

    await secondaryTap(tester, title());
    expect(menuItems, findsWidgets, reason: 'right-click');
    await tester.tapAt(const Offset(2, 2));
    await expectMenuClosed(tester);

    await keyboardOpen(tester, title());
    expect(menuItems, findsWidgets, reason: 'menu key');
    await tester.tapAt(const Offset(2, 2));
    await expectMenuClosed(tester);

    expect(semanticsActionLabels(tester), contains('Copy title'));
    semantics.dispose();
  });

  testWidgets('in edit mode no menu opens and no semantics actions exist', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester);
    await toggleCustomize(tester);
    expect(
      find.text('Done', skipOffstage: false),
      findsOneWidget,
      reason: 'edit mode is on',
    );

    await longPress(tester, title());
    expect(menuItems, findsNothing, reason: 'long-press');

    await secondaryTap(tester, title());
    expect(menuItems, findsNothing, reason: 'right-click');

    await keyboardOpen(tester, title());
    expect(menuItems, findsNothing, reason: 'menu key');

    expect(semanticsActionLabels(tester), isEmpty);
    semantics.dispose();
  });

  testWidgets('leaving edit mode turns the menu back on', (tester) async {
    await pumpHome(tester);
    await toggleCustomize(tester);
    await toggleCustomize(tester);
    expect(find.text('Done', skipOffstage: false), findsNothing);

    await longPress(tester, title());
    expect(menuItems, findsWidgets);
  });
}
