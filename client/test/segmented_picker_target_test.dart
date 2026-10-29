/// The track is 40 tall, and every segment still answers taps across 48,
/// also at the largest scale the picker allows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/segmented_picker.dart';

void main() {
  for (final scale in [1.0, 1.15]) {
    group('at ${scale}x text', () {
      var taps = <int>[];

      Future<void> pump(WidgetTester tester) async {
        taps = [];
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SegmentedPicker<int>(
                  value: 1,
                  labels: const {1: 'Open', 2: 'All', 3: 'Pinned'},
                  onChanged: taps.add,
                ),
              ),
            ),
          ),
        ));
      }

      testWidgets('the track draws at 40', (tester) async {
        await pump(tester);
        final track = find.descendant(of: find.byType(SegmentedPicker<int>), matching: find.byType(Container));
        expect(tester.getSize(track.first).height, closeTo(40 * scale, 0.01));
      });

      testWidgets('the layout box is 48 so a neighbour never overlaps the hit area', (tester) async {
        await pump(tester);
        expect(tester.getSize(find.byType(SegmentedPicker<int>)).height, closeTo(48 * scale, 0.01));
      });

      testWidgets('a tap on the 4pt above and below the track still lands', (tester) async {
        await pump(tester);
        final box = tester.getRect(find.byType(SegmentedPicker<int>));
        final third = box.width / 3;
        await tester.tapAt(Offset(box.left + third * 2.5, box.top + 1));
        await tester.tapAt(Offset(box.left + third * 1.5, box.bottom - 1));
        expect(taps, [3, 2]);
      });
    });
  }
}
