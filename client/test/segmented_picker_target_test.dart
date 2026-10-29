/// Every segment is a 48pt tap target, also at the largest scale the picker allows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/segmented_picker.dart';

void main() {
  for (final scale in [1.0, 1.15]) {
    testWidgets('segments are at least 48 tall at ${scale}x text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.from(ColorScheme.fromSeed(seedColor: const Color(0xFFF76902))),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SegmentedPicker<int>(value: 1, labels: const {1: 'Open', 2: 'All', 3: 'Pinned'}, onChanged: (_) {}),
          ),
        ),
      ));
      final segments = find.byType(InkWell);
      expect(segments, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(segments.at(i)).height, greaterThanOrEqualTo(48), reason: 'segment $i');
      }
    });
  }
}
