import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('badge shape matrix', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Rubik'),
        home: const _BadgeShapeMatrix(),
      ),
    );
    await expectLater(
      find.byType(_BadgeShapeMatrix),
      matchesGoldenFile('goldens/badge_shape_matrix.png'),
    );
  });
}

class _BadgeShapeMatrix extends StatelessWidget {
  const _BadgeShapeMatrix();

  static const _points = [6, 7, 8];
  static const _ratios = [0.90, 0.93, 0.96];

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xfff8f1e7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Badge shape matrix at 88 px',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              for (final points in _points) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final ratio in _ratios)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              color: const Color(0xffef6300),
                              shape: StarBorder(
                                points: points.toDouble(),
                                innerRadiusRatio: ratio,
                                pointRounding: 0.5,
                                valleyRounding: 0.5,
                              ),
                              child: const SizedBox(
                                width: 88,
                                height: 88,
                                child: Center(
                                  child: Text(
                                    '42',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('$points points\nratio ${ratio.toStringAsFixed(2)}',
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                  ],
                ),
                if (points != _points.last) const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      );
}
