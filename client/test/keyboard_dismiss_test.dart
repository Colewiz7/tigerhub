/// The keyboard only opens when a field is tapped, and always goes away.
///
/// Reported from TestFlight build 3: the keyboard came up on its own on Today
/// and Dining and nothing dismissed it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/screens/events_screen.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/tab_bar.dart';
import 'package:tigerhub/widgets/wordmark.dart';

class _Backend implements Backend {
  static String name(int id) => 'Place number $id';

  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async {
    if (path == '/makerspace/hours') return {'items': <dynamic>[]};
    final List<Map<String, dynamic>> data;
    switch (path) {
      case '/dining':
        data = [
          for (var i = 0; i < 20; i++)
            {
              'id': i,
              'name': name(i),
              'category': 'cat',
              'category_name': 'Category',
              'category_order': 0,
              'is_open': true,
              'today': <dynamic>[],
            },
        ];
      case '/events':
        final now = DateTime.now().toIso8601String();
        data = [
          for (var i = 0; i < 20; i++)
            {'uid': 'e$i', 'source': 'test', 'title': 'Event number $i', 'starts_at': now},
        ];
      default:
        data = [];
    }
    return {'data': data, 'stale': false, 'last_updated': null};
  }

  @override
  void close() {}
}

/// The default test platform, then iOS.
class _Platforms extends TestVariant<TargetPlatform?> {
  const _Platforms();

  @override
  Iterable<TargetPlatform?> get values => const [null, TargetPlatform.iOS];

  @override
  String describeValue(TargetPlatform? value) => value == null ? 'default platform' : value.name;

  @override
  Future<TargetPlatform?> setUp(TargetPlatform? value) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = value;
    return previous;
  }

  @override
  Future<void> tearDown(TargetPlatform? value, TargetPlatform? memento) async {
    debugDefaultTargetPlatformOverride = memento;
  }
}

const _platforms = _Platforms();

const _tabs = <String, Type>{
  'TODAY': HomeScreen,
  'DINING': DiningScreen,
  'EVENTS': EventsScreen,
  'MAP': MapScreen,
  'CAMPUS': CampusScreen,
};

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final scheme = SchemeController();
    await scheme.load();
    addTearDown(scheme.dispose);

    await tester.pumpWidget(MaterialApp(
      home: AppShell(api: ApiClient(backend: _Backend()), scheme: scheme),
    ));
    await tester.pumpAndSettle();
  }

  void expectNoField(WidgetTester tester, String where) {
    final primary = FocusManager.instance.primaryFocus;
    expect(primary?.context?.findAncestorWidgetOfExactType<EditableText>(), isNull,
        reason: 'a text field has focus $where');
    expect(tester.testTextInput.hasAnyClients, isFalse,
        reason: 'a text input is attached $where');
  }

  Finder search(Type screen) => find.descendant(
        of: find.byType(screen),
        matching: find.byType(TextField),
      );

  bool focused(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).focusNode!.hasFocus;

  Future<void> focusDiningSearch(WidgetTester tester) async {
    await tester.tap(find.text('DINING'));
    await tester.pumpAndSettle();
    await tester.tap(search(DiningScreen));
    await tester.pump();
    expect(focused(tester, search(DiningScreen)), isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
  }

  testWidgets('launch leaves no text field focused', (tester) async {
    await pumpShell(tester);
    expectNoField(tester, 'after launch');
  }, variant: _platforms);

  testWidgets('every tab switch leaves no text field focused', (tester) async {
    await pumpShell(tester);

    for (final tab in [..._tabs.keys, ..._tabs.keys]) {
      await tester.tap(find.text(tab));
      await tester.pump();
      await tester.pump();
      expectNoField(tester, 'after tapping $tab');
    }
    for (final digit in [..._digits, ..._digits.reversed]) {
      await tester.sendKeyEvent(digit);
      await tester.pump();
      await tester.pump();
      expectNoField(tester, 'after pressing ${digit.keyLabel}');
    }

    // a field used earlier is not brought back by a switch
    await focusDiningSearch(tester);
    for (final tab in ['TODAY', 'DINING', 'EVENTS', 'DINING']) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.text(tab));
      await tester.pump();
      await tester.pump();
      expectNoField(tester, 'after returning to $tab');
    }
  }, variant: _platforms);

  testWidgets('tapping outside a search field unfocuses it', (tester) async {
    await pumpShell(tester);
    await focusDiningSearch(tester);

    await tester.tap(find.byType(Wordmark));
    await tester.pump();
    expect(focused(tester, search(DiningScreen)), isFalse);
    expectNoField(tester, 'after tapping outside');
  }, variant: _platforms);

  testWidgets('dragging a list dismisses the keyboard', (tester) async {
    await pumpShell(tester);
    await focusDiningSearch(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(focused(tester, search(DiningScreen)), isFalse);
    expectNoField(tester, 'after dragging the list');
  }, variant: _platforms);

  testWidgets('every scrollable in the shell dismisses the keyboard on drag',
      (tester) async {
    await pumpShell(tester);

    void check(String where) {
      final views = find.byWidgetPredicate(
        (w) => w is ScrollView || w is SingleChildScrollView,
        skipOffstage: false,
      );
      expect(views, findsWidgets);
      for (final element in views.evaluate()) {
        final widget = element.widget;
        final behavior = widget is ScrollView
            ? widget.keyboardDismissBehavior
            : (widget as SingleChildScrollView).keyboardDismissBehavior;
        expect(behavior, ScrollViewKeyboardDismissBehavior.onDrag,
            reason: '${widget.runtimeType} on $where keeps the keyboard up on drag');
      }
    }

    for (final tab in _tabs.keys) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      check(tab);
    }
    await tester.tap(find.bySemanticsLabel('Open settings'));
    await tester.pumpAndSettle();
    check('settings');
  });

  testWidgets('closing a sheet does not bring the keyboard back',
      (tester) async {
    await pumpShell(tester);
    await focusDiningSearch(tester);

    await tester.tap(find.text(_Backend.name(0)));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expectNoField(tester, 'after closing the sheet');
  }, variant: _platforms);

  testWidgets('cancel shows while focused, clears the query and unfocuses',
      (tester) async {
    await pumpShell(tester);
    expect(find.text('Cancel'), findsNothing);
    await focusDiningSearch(tester);

    await tester.enterText(search(DiningScreen), 'number 1');
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tester.widget<TextField>(search(DiningScreen)).controller!.text, isEmpty);
    expect(focused(tester, search(DiningScreen)), isFalse);
    expect(find.text('Cancel'), findsNothing);
    expectNoField(tester, 'after cancel');
  }, variant: _platforms);

  testWidgets('the tab bar never sits above the keyboard', (tester) async {
    await pumpShell(tester);
    await focusDiningSearch(tester);

    const keyboard = 300.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    const top = 844 - keyboard;
    for (final element in find.byType(AppTabBar).evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.top, greaterThanOrEqualTo(top),
          reason: 'the tab bar rides on the keyboard at $rect');
    }
    expect(tester.getRect(search(DiningScreen)).bottom, lessThanOrEqualTo(top),
        reason: 'the search field is under the keyboard');

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(AppTabBar), findsOneWidget,
        reason: 'the tab bar did not come back with the keyboard down');
  }, variant: _platforms);
}
