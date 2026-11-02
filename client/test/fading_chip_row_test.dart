/// The Dining filter chips fade at the right edge only while more are off
/// screen, and keep that right when the width or the chips change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/screens/dining_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required double width, int chips = 6}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: FadingChipRow(
              children: [
                for (var i = 0; i < chips; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(width: 100, height: 48, child: Text('Chip $i')),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  bool fading(WidgetTester tester) => tester.state<FadingChipRowState>(find.byType(FadingChipRow)).fading;

  testWidgets('fades while chips are clipped', (tester) async {
    await pump(tester, width: 300);
    expect(fading(tester), isTrue);
  });

  testWidgets('no fade when everything fits', (tester) async {
    await pump(tester, width: 1000);
    expect(fading(tester), isFalse);
  });

  testWidgets('the fade follows a width change', (tester) async {
    await pump(tester, width: 300);
    expect(fading(tester), isTrue);
    await pump(tester, width: 1000);
    expect(fading(tester), isFalse);
    await pump(tester, width: 300);
    expect(fading(tester), isTrue);
  });

  testWidgets('the fade follows a change of chips', (tester) async {
    await pump(tester, width: 400, chips: 2);
    expect(fading(tester), isFalse);
    await pump(tester, width: 400, chips: 6);
    expect(fading(tester), isTrue);
  });

  testWidgets('the fade ends at the end of the row', (tester) async {
    await pump(tester, width: 300);
    await tester.drag(find.byType(FadingChipRow), const Offset(-2000, 0));
    await tester.pump();
    expect(fading(tester), isFalse);
  });
}
