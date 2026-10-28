/// The keyboard only opens when a field is tapped, and always goes away.
///
/// Reported from TestFlight build 3: the keyboard came up on its own on Today
/// and Dining and nothing dismissed it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/app_shell.dart';
import 'package:tigerhub/data/backend.dart';
import 'package:tigerhub/screens/campus_screen.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/screens/dining_screen.dart';
import 'package:tigerhub/screens/events_screen.dart';
import 'package:tigerhub/screens/map_screen.dart';
import 'package:tigerhub/home_screen.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/dynamic_theme.dart';
import 'package:tigerhub/widgets/campus_map.dart';
import 'package:tigerhub/widgets/places_sheet.dart';
import 'package:tigerhub/widgets/tab_bar.dart';
import 'package:tigerhub/widgets/wordmark.dart';

import 'support/tabs.dart';

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

class _PlacesBackend implements Backend {
  @override
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? q]) async => {
    'data': [
      {'id': 1, 'kind': 'water', 'kind_name': 'Water fountains', 'name': 'Golisano fountain', 'building': 'GOL', 'note': 'By the Golisano stairs'},
      {'id': 2, 'kind': 'water', 'kind_name': 'Water fountains', 'name': 'Shed fountain', 'building': 'SHED', 'note': 'By the Shed doors'},
    ],
    'stale': false,
    'last_updated': null,
  };

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
  'Today': HomeScreen,
  'Dining': DiningScreen,
  'Events': EventsScreen,
  'Map': MapScreen,
  'Campus': CampusScreen,
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
    await tester.tap(tabLabel('Dining'));
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
      await tester.tap(tabLabel(tab));
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

    // leave Dining with the field still focused, so its scope remembers it
    // onSelect skips the tap outside that would unfocus it first
    AppTabBar bar() => tester.widget<AppTabBar>(find.byType(AppTabBar));
    Future<void> select(int index) async {
      bar().onSelect(index);
      await tester.pump();
      await tester.pump();
    }

    await focusDiningSearch(tester);
    await select(0);
    expectNoField(tester, 'after leaving Dining focused');
    await select(1);
    expectNoField(tester, 'after returning to Dining');
    expect(focused(tester, search(DiningScreen)), isFalse);

    await tester.tap(search(DiningScreen));
    await tester.pump();
    await select(2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    await tester.pump();
    expect(find.byType(DiningScreen), findsOneWidget);
    expectNoField(tester, 'after returning to Dining by digit');
    await tester.tap(tabLabel('Events'));
    await tester.pump();
    await tester.tap(tabLabel('Dining'));
    await tester.pump();
    await tester.pump();
    expectNoField(tester, 'after returning to Dining by tap');
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
      await tester.tap(tabLabel(tab));
      await tester.pumpAndSettle();
      check(tab);
    }
    await tester.tap(find.bySemanticsLabel('Open settings'));
    await tester.pumpAndSettle();
    check('settings');
  });

  testWidgets('closing a detail page does not bring the keyboard back',
      (tester) async {
    await pumpShell(tester);
    await focusDiningSearch(tester);

    await tester.tap(find.text(_Backend.name(0)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expectNoField(tester, 'after closing the sheet');
  }, variant: _platforms);

  testWidgets('cancel shows while focused, clears the query and unfocuses',
      (tester) async {
    await pumpShell(tester);
    expect(find.text('Cancel'), findsNothing);
    await focusDiningSearch(tester);

    final first = find.text(_Backend.name(0));
    expect(first, findsOneWidget);
    await tester.enterText(search(DiningScreen), 'number 1');
    await tester.pump();
    expect(first, findsNothing, reason: 'the query did not filter');
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tester.widget<TextField>(search(DiningScreen)).controller!.text, isEmpty);
    expect(focused(tester, search(DiningScreen)), isFalse);
    expect(find.text('Cancel'), findsNothing);
    expect(first, findsOneWidget, reason: 'the list stayed filtered');
    expectNoField(tester, 'after cancel');
  }, variant: _platforms);

  group('map search', () {
    const west = CampusMapFeature(
      id: 1,
      kind: 'water',
      kindName: 'Water fountains',
      name: 'West fountain',
      geometryType: 'Point',
      coordinates: [
        [GeoCoordinate(-77.68, 43.08)],
      ],
      building: 'GOL',
    );
    const east = CampusMapFeature(
      id: 2,
      kind: 'aed',
      kindName: 'Defibrillators',
      name: 'East AED',
      geometryType: 'Point',
      coordinates: [
        [GeoCoordinate(-77.67, 43.09)],
      ],
      building: 'SHED',
    );

    Future<void> pumpMap(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CampusMapView(
              result: Result(
                value: const Collection(data: [west, east], stale: false),
                state: DataState.ok,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Search campus places (Ctrl+F)'));
      await tester.pumpAndSettle();
    }

    final field = find.byType(TextField);
    bool fieldFocused(WidgetTester tester) =>
        tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus;

    testWidgets('opening it does not focus the field', (tester) async {
      await pumpMap(tester);
      await openSearch(tester);
      expect(field, findsOneWidget);
      expect(fieldFocused(tester), isFalse);
      expectNoField(tester, 'after opening map search');
    }, variant: _platforms);

    testWidgets('a tap focuses the field and a drag dismisses it',
        (tester) async {
      await pumpMap(tester);
      await openSearch(tester);
      await tester.tap(field);
      await tester.pump();
      expect(fieldFocused(tester), isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expectNoField(tester, 'after dragging the results');
    }, variant: _platforms);

    testWidgets('cancel clears the query, unfocuses and shows every place',
        (tester) async {
      await pumpMap(tester);
      await openSearch(tester);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'East');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'West fountain'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(fieldFocused(tester), isFalse);
      expect(find.text('Cancel'), findsNothing);
      expect(find.widgetWithText(ListTile, 'West fountain'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'East AED'), findsOneWidget);
      expectNoField(tester, 'after cancel');
    }, variant: _platforms);

    testWidgets('picking a result moves the camera inside the pan bounds',
        (tester) async {
      await pumpMap(tester);
      await openSearch(tester);
      await tester.tap(field);
      await tester.enterText(field, 'East AED');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'East AED'));
      await tester.pumpAndSettle();

      final viewer = find.byType(InteractiveViewer);
      final matrix = tester.widget<InteractiveViewer>(viewer).transformationController!.value;
      final size = tester.getSize(viewer);
      const scale = 2.4;
      expect(matrix.getMaxScaleOnAxis(), scale);
      expect(matrix.entry(0, 3), inInclusiveRange(size.width * (1 - scale) - 80, 80));
      expect(matrix.entry(1, 3), inInclusiveRange(size.height * (1 - scale) - 80, 80));
      expect(find.text('East AED'), findsWidgets, reason: 'the pick is not selected');
      expectNoField(tester, 'after picking a result');
    }, variant: _platforms);
  });

  testWidgets('the places sheet search has cancel', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlacesSheet(
          api: ApiClient(backend: _PlacesBackend()),
          kind: 'water',
          title: 'Water fountains',
          icon: AppIconKind.water,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    final shed = find.text('By the Shed doors');
    expect(shed, findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'Golisano');
    await tester.pump();
    expect(shed, findsNothing, reason: 'the query did not filter');
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('Cancel'), findsNothing);
    expect(shed, findsOneWidget, reason: 'the list stayed filtered');
    expectNoField(tester, 'after cancel in the places sheet');
  }, variant: _platforms);

  test('every scroll view in lib dismisses the keyboard on drag', () {
    final constructor = RegExp(r'\b(ListView|GridView|CustomScrollView|SingleChildScrollView|ReorderableListView)(\.\w+)?\(');
    final missing = <String>[];
    var seen = 0;
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsLinesSync().map((l) => l.trimLeft().startsWith('//') ? '' : l).join('\n');
      for (final match in constructor.allMatches(source)) {
        seen++;
        // only the constructor's own arguments, not nested ones
        var depth = 0;
        var found = false;
        for (var i = match.end - 1; i < source.length; i++) {
          final c = source[i];
          if (c == '(' || c == '[' || c == '{') depth++;
          if (c == ')' || c == ']' || c == '}') depth--;
          if (depth == 0) break;
          if (depth == 1 && source.startsWith('keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag', i)) found = true;
        }
        if (!found) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          missing.add('${file.path}:$line ${match.group(0)}');
        }
      }
    }
    expect(seen, greaterThan(30), reason: 'the scan found too few scroll views to be right');
    expect(missing, isEmpty, reason: 'scroll views without keyboardDismissBehavior: onDrag');
  });

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
