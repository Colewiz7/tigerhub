/// A list that fits its box exactly, counting whatever it withholds.
///
/// Cards live in a uniform height grid. A hardcoded row cap is a guess that
/// breaks at a different window size or text scale, and the overflow is then
/// clipped silently by the grid cell. This measures the space available and
/// shows only the rows that genuinely fit, so the "+N more" footer is always
/// visible and nothing is ever cut off without being counted.
///
/// Row height is enforced rather than measured, so the arithmetic is exact.
library;

import 'package:flutter/material.dart';

import 'more_row.dart';

class BoundedList extends StatelessWidget {
  const BoundedList({
    super.key,
    required this.itemCount,
    required this.itemHeight,
    required this.itemBuilder,
    required this.noun,
    this.onShowAll,
    this.footerHeight = 34,
  });

  final int itemCount;
  final double itemHeight;
  final Widget Function(BuildContext, int) itemBuilder;
  final String noun;
  final VoidCallback? onShowAll;
  final double footerHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : itemHeight * itemCount + footerHeight;

        // Assume a footer is needed, then check whether everything fits after
        // all. Reserving the space up front is what keeps it on screen.
        var fits = ((available - footerHeight) / itemHeight).floor();
        if (fits >= itemCount) {
          // No footer needed, so the whole box is available for rows.
          fits = (available / itemHeight).floor();
        }
        final shown = fits.clamp(0, itemCount);
        final hidden = itemCount - shown;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < shown; i++)
              SizedBox(height: itemHeight, child: itemBuilder(context, i)),
            if (hidden > 0)
              SizedBox(
                height: footerHeight,
                child: MoreRow(hidden: hidden, noun: noun, onTap: onShowAll),
              ),
          ],
        );
      },
    );
  }
}
