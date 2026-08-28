/// Segmented linear indicator.
///
/// Two pieces with a gap rather than one continuous bar, so it reads as a
/// deliberate indicator rather than a loading bar.
library;

import 'package:flutter/material.dart';

class SegmentedBar extends StatelessWidget {
  const SegmentedBar({
    super.key,
    required this.value,
    this.width = 54,
    this.height = 6,
    this.gap = 4,
  });

  final double value;
  final double width;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = value.clamp(0.0, 1.0);
    // The first segment carries the first half of the range, the second the
    // rest, so a low value leaves the second piece entirely unlit.
    final first = (clamped / 0.5).clamp(0.0, 1.0);
    final second = ((clamped - 0.5) / 0.5).clamp(0.0, 1.0);

    Widget segment(double fill) => Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: Stack(
              children: [
                Container(height: height, color: scheme.surfaceContainerHighest),
                FractionallySizedBox(
                  widthFactor: fill,
                  child: Container(height: height, color: scheme.primary),
                ),
              ],
            ),
          ),
        );

    return SizedBox(
      width: width,
      height: height,
      child: Row(
        children: [segment(first), SizedBox(width: gap), segment(second)],
      ),
    );
  }
}
