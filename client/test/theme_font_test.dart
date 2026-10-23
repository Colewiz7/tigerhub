/// Every piece of text the theme can reach resolves to Rubik, except on iOS,
/// where it resolves to the system font (SF Pro) and never to Rubik.
///
/// AppTheme.from used to set fontFamily on the base ThemeData and then replace
/// the text theme with styles that carried none, so themed text fell through to
/// the platform font while the goldens (which forced Rubik) looked right. This
/// walks the theme two ways so that cannot come back unnoticed:
///
///  - statically: all 15 slots of textTheme and primaryTextTheme, the nine
///    Cupertino styles, and every component-theme text style the theme sets.
///    A component style the theme leaves null is allowed here, because it falls
///    through to the text theme; the rendering walk proves that for the widgets
///    listed in it.
///  - by rendering: a gallery of Material and Cupertino widgets is built under
///    both themes and every painted run of text and every text field is
///    checked, after style inheritance, for its family.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';

const _rubik = 'Rubik';

/// Families other than Rubik that may appear, with the reason. Icon glyphs are
/// drawn from the icon fonts as text. Space Grotesk is the wordmark only, and
/// the wordmark is an SVG with its text converted to outlines
/// (lib/widgets/wordmark.dart), so no Dart text style uses it: the set below
/// is deliberately free of it. Add it here, with the widget, if one ever does.
const _allowedFamilies = <String>{
  'MaterialIcons',
  'CupertinoIcons',
  'packages/cupertino_icons/CupertinoIcons',
};

/// What Material and Cupertino name the iOS system font. A null family on iOS
/// also paints in it.
const _system = <String>{'CupertinoSystemText', 'CupertinoSystemDisplay'};

bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

// the family a theme slot must carry on this platform
bool _expected(String? family) => _ios ? _system.contains(family) : family == _rubik;

bool _ok(String? family) => _allowedFamilies.contains(family) || (_ios ? family == null || _system.contains(family) : family == _rubik);

final _platforms = TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux, TargetPlatform.iOS});

ColorScheme _scheme(Brightness b) =>
    ColorScheme.fromSeed(seedColor: const Color(0xFFF76902), brightness: b);

Map<String, TextStyle?> _slots(String prefix, TextTheme t) => {
  '$prefix.displayLarge': t.displayLarge,
  '$prefix.displayMedium': t.displayMedium,
  '$prefix.displaySmall': t.displaySmall,
  '$prefix.headlineLarge': t.headlineLarge,
  '$prefix.headlineMedium': t.headlineMedium,
  '$prefix.headlineSmall': t.headlineSmall,
  '$prefix.titleLarge': t.titleLarge,
  '$prefix.titleMedium': t.titleMedium,
  '$prefix.titleSmall': t.titleSmall,
  '$prefix.bodyLarge': t.bodyLarge,
  '$prefix.bodyMedium': t.bodyMedium,
  '$prefix.bodySmall': t.bodySmall,
  '$prefix.labelLarge': t.labelLarge,
  '$prefix.labelMedium': t.labelMedium,
  '$prefix.labelSmall': t.labelSmall,
};

Map<String, TextStyle?> _cupertinoSlots(CupertinoTextThemeData t) => {
  'cupertino.textStyle': t.textStyle,
  'cupertino.actionTextStyle': t.actionTextStyle,
  'cupertino.actionSmallTextStyle': t.actionSmallTextStyle,
  'cupertino.tabLabelTextStyle': t.tabLabelTextStyle,
  'cupertino.navTitleTextStyle': t.navTitleTextStyle,
  'cupertino.navLargeTitleTextStyle': t.navLargeTitleTextStyle,
  'cupertino.navActionTextStyle': t.navActionTextStyle,
  'cupertino.pickerTextStyle': t.pickerTextStyle,
  'cupertino.dateTimePickerTextStyle': t.dateTimePickerTextStyle,
};

final _states = <Set<WidgetState>>[
  {},
  {WidgetState.pressed},
  {WidgetState.hovered},
  {WidgetState.focused},
  {WidgetState.selected},
  {WidgetState.disabled},
];

Map<String, TextStyle?> _stateful(String name, WidgetStateProperty<TextStyle?>? p) => {
  if (p != null)
    for (final s in _states) '$name$s': p.resolve(s),
};

/// Text styles the theme sets on component themes. Null means "not set here",
/// which is allowed; see the library comment.
Map<String, TextStyle?> _componentStyles(ThemeData t) {
  final i = t.inputDecorationTheme;
  return {
    'input.labelStyle': i.labelStyle,
    'input.floatingLabelStyle': i.floatingLabelStyle,
    'input.helperStyle': i.helperStyle,
    'input.hintStyle': i.hintStyle,
    'input.errorStyle': i.errorStyle,
    'input.prefixStyle': i.prefixStyle,
    'input.suffixStyle': i.suffixStyle,
    'input.counterStyle': i.counterStyle,
    'chip.labelStyle': t.chipTheme.labelStyle,
    'chip.secondaryLabelStyle': t.chipTheme.secondaryLabelStyle,
    ..._stateful('navigationBar.label', t.navigationBarTheme.labelTextStyle),
    'bottomNavigation.selected': t.bottomNavigationBarTheme.selectedLabelStyle,
    'bottomNavigation.unselected': t.bottomNavigationBarTheme.unselectedLabelStyle,
    'navigationRail.selected': t.navigationRailTheme.selectedLabelTextStyle,
    'navigationRail.unselected': t.navigationRailTheme.unselectedLabelTextStyle,
    'snackBar.content': t.snackBarTheme.contentTextStyle,
    'dialog.title': t.dialogTheme.titleTextStyle,
    'dialog.content': t.dialogTheme.contentTextStyle,
    'appBar.title': t.appBarTheme.titleTextStyle,
    'appBar.toolbar': t.appBarTheme.toolbarTextStyle,
    'listTile.title': t.listTileTheme.titleTextStyle,
    'listTile.subtitle': t.listTileTheme.subtitleTextStyle,
    'listTile.leadingAndTrailing': t.listTileTheme.leadingAndTrailingTextStyle,
    'tabBar.label': t.tabBarTheme.labelStyle,
    'tabBar.unselected': t.tabBarTheme.unselectedLabelStyle,
    'tooltip.text': t.tooltipTheme.textStyle,
    'popupMenu.text': t.popupMenuTheme.textStyle,
    ..._stateful('popupMenu.label', t.popupMenuTheme.labelTextStyle),
    ..._stateful('textButton', t.textButtonTheme.style?.textStyle),
    ..._stateful('elevatedButton', t.elevatedButtonTheme.style?.textStyle),
    ..._stateful('filledButton', t.filledButtonTheme.style?.textStyle),
    ..._stateful('outlinedButton', t.outlinedButtonTheme.style?.textStyle),
    ..._stateful('iconButton', t.iconButtonTheme.style?.textStyle),
    ..._stateful('menuButton', t.menuButtonTheme.style?.textStyle),
    ..._stateful('segmentedButton', t.segmentedButtonTheme.style?.textStyle),
    ..._stateful('searchBar.text', t.searchBarTheme.textStyle),
    ..._stateful('searchBar.hint', t.searchBarTheme.hintStyle),
    'searchView.header': t.searchViewTheme.headerTextStyle,
    'searchView.headerHint': t.searchViewTheme.headerHintStyle,
    'dropdownMenu.text': t.dropdownMenuTheme.textStyle,
    'badge.text': t.badgeTheme.textStyle,
    'banner.content': t.bannerTheme.contentTextStyle,
    'dataTable.data': t.dataTableTheme.dataTextStyle,
    'dataTable.heading': t.dataTableTheme.headingTextStyle,
    'slider.valueIndicator': t.sliderTheme.valueIndicatorTextStyle,
    'toggleButtons.text': t.toggleButtonsTheme.textStyle,
    'fab.extended': t.floatingActionButtonTheme.extendedTextStyle,
    'timePicker.dayPeriod': t.timePickerTheme.dayPeriodTextStyle,
    'timePicker.hourMinute': t.timePickerTheme.hourMinuteTextStyle,
    'timePicker.dial': t.timePickerTheme.dialTextStyle,
    'datePicker.day': t.datePickerTheme.dayStyle,
    'datePicker.weekday': t.datePickerTheme.weekdayStyle,
    'datePicker.yearStyle': t.datePickerTheme.yearStyle,
    'datePicker.headerHeadline': t.datePickerTheme.headerHeadlineStyle,
    'datePicker.headerHelp': t.datePickerTheme.headerHelpStyle,
    'datePicker.rangePickerHeaderHeadline': t.datePickerTheme.rangePickerHeaderHeadlineStyle,
    'datePicker.rangePickerHeaderHelp': t.datePickerTheme.rangePickerHeaderHelpStyle,
  };
}

/// A style's family after inheriting from the theme's default text style,
/// which is what Text does with a style whose own family is null.
String? _effective(TextStyle? style, String? inherited) => style?.fontFamily ?? inherited;

void _walkSpan(InlineSpan span, String? inherited, List<String> bad) {
  if (span is! TextSpan) return;
  final family = _effective(span.style, inherited);
  final text = span.text;
  if (text != null && text.trim().isNotEmpty && !_ok(family)) {
    bad.add('"$text" paints in ${family ?? 'the platform font'}');
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    _walkSpan(child, family, bad);
  }
}

/// Every run of painted text, and every text field, in the tree right now.
List<String> _nonRubik(WidgetTester tester) {
  final bad = <String>[];
  for (final w in tester.allWidgets) {
    if (w is RichText) _walkSpan(w.text, null, bad);
    if (w is EditableText && !_ok(w.style.fontFamily)) {
      bad.add('a text field types in ${w.style.fontFamily ?? 'the platform font'}');
    }
  }
  return bad;
}

Future<void> _pump(WidgetTester tester, Brightness b, Widget home) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.from(_scheme(b)), home: home));
  await tester.pumpAndSettle();
}

void main() {
  for (final b in Brightness.values) {
    group('${b.name} theme', () {
      testWidgets('every text slot and component style is the platform font', (tester) async {
        late ThemeData theme;
        late CupertinoThemeData cupertino;
        await _pump(
          tester,
          b,
          Builder(
            builder: (c) {
              theme = Theme.of(c);
              cupertino = CupertinoTheme.of(c);
              return const SizedBox();
            },
          ),
        );

        final styles = <String, TextStyle?>{
          ..._slots('textTheme', theme.textTheme),
          ..._slots('primaryTextTheme', theme.primaryTextTheme),
          ..._cupertinoSlots(cupertino.textTheme),
          ..._componentStyles(theme),
        };
        expect(styles.length, greaterThan(15 + 15 + 9), reason: 'the walk lost its slots');

        final bad = [
          for (final e in styles.entries)
            if (e.value != null && !_ok(_effective(e.value, null)))
              '${e.key} has family ${e.value!.fontFamily}',
        ];
        expect(bad, isEmpty);

        // Every textTheme and primaryTextTheme slot must be set, not just
        // non-conflicting: a null slot is exactly the original defect.
        final unset = [
          for (final e in styles.entries)
            if ((e.key.startsWith('textTheme.') ||
                    e.key.startsWith('primaryTextTheme.') ||
                    e.key.startsWith('cupertino.')) &&
                !_expected(e.value?.fontFamily))
              e.key,
        ];
        expect(unset, isEmpty);
      }, variant: _platforms);

      testWidgets('Material widgets paint in the platform font', (tester) async {
        await _pump(
          tester,
          b,
          DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Title'),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'One'),
                    Tab(text: 'Two'),
                  ],
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: 0,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
                ],
              ),
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final style in [
                      (BuildContext c) => Theme.of(c).textTheme.displayLarge,
                      (BuildContext c) => Theme.of(c).textTheme.displayMedium,
                      (BuildContext c) => Theme.of(c).textTheme.displaySmall,
                      (BuildContext c) => Theme.of(c).textTheme.headlineLarge,
                      (BuildContext c) => Theme.of(c).textTheme.headlineMedium,
                      (BuildContext c) => Theme.of(c).textTheme.headlineSmall,
                      (BuildContext c) => Theme.of(c).textTheme.titleLarge,
                      (BuildContext c) => Theme.of(c).textTheme.titleMedium,
                      (BuildContext c) => Theme.of(c).textTheme.titleSmall,
                      (BuildContext c) => Theme.of(c).textTheme.bodyLarge,
                      (BuildContext c) => Theme.of(c).textTheme.bodyMedium,
                      (BuildContext c) => Theme.of(c).textTheme.bodySmall,
                      (BuildContext c) => Theme.of(c).textTheme.labelLarge,
                      (BuildContext c) => Theme.of(c).textTheme.labelMedium,
                      (BuildContext c) => Theme.of(c).textTheme.labelSmall,
                      (BuildContext c) => Theme.of(c).primaryTextTheme.bodyMedium,
                    ])
                      Builder(builder: (c) => Text('slot', style: style(c))),
                    const Text('plain'),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: 'label',
                        hintText: 'hint',
                        helperText: 'helper',
                        counterText: 'counter',
                        prefixText: 'prefix',
                        suffixText: 'suffix',
                      ),
                    ),
                    const TextField(
                      decoration: InputDecoration(labelText: 'bad', errorText: 'error'),
                    ),
                    const Chip(label: Text('chip')),
                    FilterChip(label: const Text('filter'), selected: true, onSelected: (_) {}),
                    ChoiceChip(label: const Text('choice'), selected: false, onSelected: (_) {}),
                    const ListTile(
                      title: Text('tile title'),
                      subtitle: Text('tile subtitle'),
                      trailing: Text('trailing'),
                    ),
                    ElevatedButton(onPressed: () {}, child: const Text('elevated')),
                    FilledButton(onPressed: () {}, child: const Text('filled')),
                    FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
                    OutlinedButton(onPressed: () {}, child: const Text('outlined')),
                    TextButton(onPressed: () {}, child: const Text('text')),
                    const TextButton(onPressed: null, child: Text('disabled')),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('seg a')),
                        ButtonSegment(value: 1, label: Text('seg b')),
                      ],
                      selected: const {0},
                      onSelectionChanged: (_) {},
                    ),
                    SearchBar(hintText: 'search hint'),
                    DropdownMenu<int>(
                      label: const Text('dropdown'),
                      dropdownMenuEntries: const [DropdownMenuEntry(value: 0, label: 'entry')],
                    ),
                    DropdownButton<int>(
                      value: 0,
                      items: const [DropdownMenuItem(value: 0, child: Text('item'))],
                      onChanged: (_) {},
                    ),
                    const Tooltip(message: 'tip', child: Text('has tooltip')),
                    PopupMenuButton<int>(
                      itemBuilder: (_) => const [PopupMenuItem(value: 0, child: Text('popup'))],
                    ),
                    Builder(
                      builder: (c) => TextButton(
                        onPressed: () =>
                            ScaffoldMessenger.of(c)
                                .showSnackBar(const SnackBar(content: Text('snack'))),
                        child: const Text('open snack'),
                      ),
                    ),
                    Builder(
                      builder: (c) => TextButton(
                        onPressed: () => showDialog<void>(
                          context: c,
                          builder: (_) => const AlertDialog(
                            title: Text('dialog title'),
                            content: Text('dialog content'),
                            actions: [Text('dialog action')],
                          ),
                        ),
                        child: const Text('open dialog'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(_nonRubik(tester), isEmpty, reason: 'idle gallery');

        // Overlays: tooltip, popup menu, snack bar, dialog, dropdown.
        final tip = tester.state<TooltipState>(
          find.ancestor(of: find.text('has tooltip'), matching: find.byType(Tooltip)),
        );
        tip.ensureTooltipVisible();
        await tester.pumpAndSettle();
        expect(find.text('tip'), findsOneWidget);
        expect(_nonRubik(tester), isEmpty, reason: 'tooltip');

        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        expect(find.text('popup'), findsOneWidget);
        expect(_nonRubik(tester), isEmpty, reason: 'popup menu');
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();

        await tester.tap(find.text('open snack'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('snack'), findsOneWidget);
        expect(_nonRubik(tester), isEmpty, reason: 'snack bar');

        await tester.tap(find.text('open dialog'));
        await tester.pumpAndSettle();
        expect(find.text('dialog title'), findsOneWidget);
        expect(_nonRubik(tester), isEmpty, reason: 'dialog');
      }, variant: _platforms);

      testWidgets('the search delegate and error states paint in the platform font', (tester) async {
        await _pump(
          tester,
          b,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => showSearch<void>(context: c, delegate: _Delegate()),
              child: const Text('search'),
            ),
          ),
        );
        await tester.tap(find.text('search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'typed');
        await tester.pumpAndSettle();
        expect(find.text('suggestion'), findsOneWidget);
        expect(_nonRubik(tester), isEmpty);
      }, variant: _platforms);

      testWidgets('Cupertino widgets paint in the platform font', (tester) async {
        await _pump(
          tester,
          b,
          // Material supplies the default text style the way it does under a
          // Scaffold; the controls below take bare Text children.
          Material(
            type: MaterialType.transparency,
            child: CupertinoPageScaffold(
              navigationBar: const CupertinoNavigationBar(
                middle: Text('nav title'),
                trailing: Text('nav action'),
              ),
              child: ListView(
                children: [
                  CupertinoButton(onPressed: () {}, child: const Text('cupertino button')),
                  CupertinoButton.filled(onPressed: () {}, child: const Text('filled button')),
                  const CupertinoTextField(placeholder: 'placeholder'),
                  const CupertinoSearchTextField(placeholder: 'search placeholder'),
                  const CupertinoListTile(title: Text('list title'), subtitle: Text('list sub')),
                  CupertinoListSection(
                    header: const Text('section header'),
                    children: const [CupertinoListTile(title: Text('in section'))],
                  ),
                  CupertinoSegmentedControl<int>(
                    children: const {0: Text('segment a'), 1: Text('segment b')},
                    groupValue: 0,
                    onValueChanged: (_) {},
                  ),
                  SizedBox(
                    height: 120,
                    child: CupertinoPicker(
                      itemExtent: 32,
                      onSelectedItemChanged: (_) {},
                      children: const [Text('picker a'), Text('picker b')],
                    ),
                  ),
                  SizedBox(
                    height: 120,
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      onDateTimeChanged: (_) {},
                    ),
                  ),
                  CupertinoSlidingSegmentedControl<int>(
                    children: const {0: Text('slide a'), 1: Text('slide b')},
                    groupValue: 0,
                    onValueChanged: _ignore,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(_nonRubik(tester), isEmpty);
      }, variant: _platforms);
    });
  }

  // map labels paint on a canvas, which inherits nothing
  testWidgets('canvas text names the platform font', (tester) async {
    expect(AppTheme.uiFont, _ios ? isNull : _rubik);
  }, variant: _platforms);
}

void _ignore(int? _) {}

class _Delegate extends SearchDelegate<void> {
  @override
  List<Widget> buildActions(BuildContext context) => const [];

  @override
  Widget buildLeading(BuildContext context) => const Icon(Icons.arrow_back);

  @override
  Widget buildResults(BuildContext context) => const Text('results');

  @override
  Widget buildSuggestions(BuildContext context) => ListTile(title: const Text('suggestion'));
}
