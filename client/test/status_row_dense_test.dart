/// The dense (phone dashboard) row never cuts a name because of its trailing
/// pill.
///
/// The pill sits beside the text only when the name still shows in full there;
/// otherwise it moves under the status. The placement is measured, so it holds
/// at any text size. A name is cut only when it needs more than two lines even
/// with the whole row to itself, and a normal row is 52 tall at 1x.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/theme/app_theme.dart';
import 'package:tigerhub/widgets/status_row.dart';

import 'golden_harness.dart';

const _names = [
  'Beanz',
  'Brick City Cafe',
  'Global Village Cantina',
  'The Reservoir at Global Village Dining Hall and Bakery',
  // 90 characters: more than two lines even with the whole row
  'Extremely Long Dining Location Name That Keeps Going And Going Past Two Lines Of Text At Any Size',
];

Widget _pill() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
  decoration: const ShapeDecoration(
    color: Colors.green,
    shape: StadiumBorder(),
  ),
  child: const Text('80%'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in const [320.0, 390.0, 440.0]) {
    for (final scale in const [1.0, 1.3, 1.5, 2.0]) {
      goldenWidgets(
        'dense rows at ${width.toInt()} wide, text ${scale}x: the pill never '
        'cuts a name, normal rows are 52 at 1x',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 4000);
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          // each name twice: with a pill, then alone as the reference
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.from(
                ColorScheme.fromSeed(seedColor: const Color(0xFFF76902)),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  // a card on a phone: 16 margin, 16 padding
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      for (final name in _names) ...[
                        StatusRow(
                          dense: true,
                          icon: Icons.restaurant_rounded,
                          title: name,
                          subtitle: 'OPEN · until 6:00 PM',
                          trailing: _pill(),
                        ),
                        StatusRow(
                          dense: true,
                          icon: Icons.restaurant_rounded,
                          title: name,
                          subtitle: 'OPEN · until 6:00 PM',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          bool cut(Finder text) =>
              tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

          for (final (i, name) in _names.indexed) {
            final both = find.text(name);
            expect(both, findsNWidgets(2), reason: name);
            final withPill = both.at(0);
            final alone = both.at(1);
            if (!cut(alone)) {
              expect(
                cut(withPill),
                isFalse,
                reason: '"$name" was cut by the pill at ${width}x$scale',
              );
            }
            // the status line is not cut by the pill either
            final status = find.text('OPEN · until 6:00 PM');
            if (!cut(status.at(2 * i + 1))) {
              expect(
                cut(status.at(2 * i)),
                isFalse,
                reason: 'the status of "$name" was cut by the pill',
              );
            }
          }

          // Normal names keep a 52 row at 1x on a 390 or 440 wide phone. On a
          // 320 wide phone the status does not fit beside a pill, so the pill
          // drops under it rather than cut the status (no cut is asserted
          // above at every width).
          if (scale == 1 && width >= 390) {
            for (final name in const [
              'Beanz',
              'Brick City Cafe',
              'Global Village Cantina',
            ]) {
              final row = find
                  .ancestor(
                    of: find.text(name).first,
                    matching: find.byType(Material),
                  )
                  .first;
              expect(tester.getSize(row).height, 52, reason: name);
            }
          }
        },
      );
    }
  }
}
