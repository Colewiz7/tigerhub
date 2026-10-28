/// On a phone, Today's rows sit flat in their card with hairlines between them,
/// like an iOS inset group. No row is its own filled surface. Rows elsewhere,
/// and Today from 600 wide, keep their fill.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tigerhub/cards/dining_card.dart';
import 'package:tigerhub/data/rit_clock.dart';
import 'package:tigerhub/models/api_models.dart';
import 'package:tigerhub/services/api.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/app_icon.dart';
import 'package:tigerhub/widgets/card_shell.dart';
import 'package:tigerhub/widgets/status_row.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    RitClock.pin(DateTime.utc(2026, 10, 14, 16));
  });

  tearDown(RitClock.reset);

  final theme = AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)));
  final dining = Result(
    value: Collection(data: [for (var i = 0; i < 6; i++) DiningLocation(id: i + 1, name: 'Hall $i', isOpen: true)], stale: false),
    state: DataState.ok,
  );

  Future<void> pump(WidgetTester tester, Widget child, {double width = 390, double ratio = 3}) async {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(width * ratio, 2400 * ratio);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: SingleChildScrollView(child: child))));
    await tester.pump();
  }

  List<Color?> rowFills(WidgetTester tester) => [
    for (final row in tester.elementList(find.byType(StatusRow)))
      tester.widget<Material>(find.descendant(of: find.byWidget(row.widget), matching: find.byType(Material)).first).color,
  ];

  testWidgets('a Today card on a phone has no filled rows', (tester) async {
    await pump(tester, DiningCard(result: dining, onShowAll: () {}));
    final scheme = theme.colorScheme;
    expect(find.byType(StatusRow), findsNWidgets(3));
    for (final fill in rowFills(tester)) {
      expect(fill, isNot(scheme.surfaceContainerHigh));
      expect(fill, Colors.transparent);
    }
  });

  testWidgets('one hairline between each pair of rows, one device pixel', (tester) async {
    await pump(tester, DiningCard(result: dining, onShowAll: () {}));
    expect(find.byType(RowSeparator), findsNWidgets(3 - 1));
    final line = tester.getSize(find.descendant(of: find.byType(RowSeparator).first, matching: find.byType(ColoredBox)));
    expect(line.height * 3, closeTo(1, 0.001));
    // inset to where the row text starts
    final card = tester.getRect(find.byType(DiningRow).first);
    expect(tester.getRect(find.descendant(of: find.byType(RowSeparator).first, matching: find.byType(ColoredBox))).left - card.left, RowSeparator.inset);
  });

  testWidgets('the same card from 600 wide keeps its filled rows', (tester) async {
    await pump(tester, SizedBox(height: 560, child: DiningCard(result: dining, onShowAll: () {})), width: 700);
    expect(find.byType(RowSeparator), findsNothing);
    for (final fill in rowFills(tester)) {
      expect(fill, theme.colorScheme.surfaceContainerHigh);
    }
  });

  testWidgets('a dense row outside a card, as on the Dining tab, keeps its fill', (tester) async {
    await pump(tester, const StatusRow(icon: AppIconKind.truck, title: 'Truck', dense: true));
    expect(rowFills(tester), [theme.colorScheme.surfaceContainerHigh]);
  });

  testWidgets('a card shell on a phone tells rows to sit flat', (tester) async {
    late bool flat;
    await pump(tester, CardShell(title: 'Card', child: Builder(builder: (context) {
      flat = CardShell.flatRowsOf(context);
      return const SizedBox();
    })));
    expect(flat, isTrue);
  });
}
