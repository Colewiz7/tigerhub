/// Real scrolling through JumpList.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/widgets/jump_list.dart';

void main() {
  List<JumpGroup> groups(int n) => [
    for (var i = 0; i < n; i++)
      JumpGroup(
        label: 'Group $i',
        icon: Icons.circle,
        count: 1,
        builder: (context) => SizedBox(height: 400, child: Text('body $i')),
      ),
  ];

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JumpList(groups: groups(30)))),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(1400, 800)]) {
    testWidgets('dragging and flinging down and up at ${size.width.toInt()}', (
      tester,
    ) async {
      await pump(tester, size);
      for (var i = 0; i < 6; i++) {
        await tester.fling(find.byType(ListView).first, const Offset(0, -1500), 3000);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 700));
        await tester.pump();
        await tester.fling(find.byType(ListView).first, const Offset(0, 1500), 3000);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final heights in [
    (n: 30, h: (int i) => i < 4 ? 900.0 : 120.0),
    (n: 30, h: (int i) => i < 4 ? 120.0 : 900.0),
    (n: 30, h: (int i) => 100.0 + (i * 137 % 11) * 120),
  ]) {
    testWidgets('the rail jumps through uneven groups (${heights.h(0)}..)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JumpList(
              groups: [
                for (var i = 0; i < heights.n; i++)
                  JumpGroup(
                    label: 'Group $i',
                    icon: Icons.circle,
                    count: 1,
                    builder: (context) => SizedBox(height: heights.h(i), child: Text('body $i')),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final i in [29, 2, 20, 0, 25, 10, 28, 1]) {
        await tester.tap(find.text('Group $i'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'jump to $i');
      }
    });
  }

  testWidgets('a list that shrinks while scrolled to the bottom', (tester) async {
    await pump(tester, const Size(390, 844));
    for (var i = 0; i < 8; i++) {
      await tester.fling(find.byType(ListView).first, const Offset(0, -2000), 4000);
      await tester.pumpAndSettle();
    }
    expect(find.text('body 29'), findsOneWidget);

    // A search narrowing the groups: the offset is now past the new end.
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JumpList(groups: groups(3)))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('body 2'), findsOneWidget);
  });
}
