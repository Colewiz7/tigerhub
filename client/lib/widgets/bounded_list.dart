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

import '../theme/tokens.dart';
import 'more_row.dart';

/// How many rows a dashboard card shows on a phone before its "+N" footer: the
/// card is as tall as its content there, so this is its height. Null (no cap)
/// at 600pt and wider, where the cell's box does the bounding.
int? phoneRowCap(BuildContext context, {int rows = 4}) =>
    Insets.phone(context) ? rows : null;

class BoundedList extends StatelessWidget {
  const BoundedList({
    super.key,
    required this.itemCount,
    required this.itemHeight,
    required this.itemBuilder,
    required this.noun,
    this.onShowAll,
    this.hiddenCountBuilder,
    this.footerHeight = 46,
    this.dense = false,
    this.maxRows,
  });

  final int itemCount;
  final double itemHeight;
  final Widget Function(BuildContext, int) itemBuilder;
  final String noun;
  final VoidCallback? onShowAll;
  final int Function(int shown)? hiddenCountBuilder;
  final double footerHeight;

  /// The phone dashboard's condensed footer: a 36 block holding one 28 text
  /// row, instead of the 46 pill block. Wider windows ignore it.
  final bool dense;

  /// Most rows shown before the footer takes over. The phone dashboard sizes a
  /// card to its content, so there is no box to measure and this is the box.
  final int? maxRows;

  /// The footer block of a dense list on a phone.
  static const double denseFooterHeight = 36;

  @override
  Widget build(BuildContext context) {
    final compact = dense && Insets.phone(context);
    final footer = compact ? denseFooterHeight : footerHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = maxRows ?? itemCount;
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : itemHeight * itemCount + footer;

        // Assume a footer is needed, then check whether everything fits after
        // all. Reserving the space up front is what keeps it on screen.
        var shown = ((available - footer) / itemHeight).floor().clamp(0, itemCount);
        if (shown > cap) shown = cap;
        if (shown >= itemCount) {
          // No footer needed, so the whole box is available for rows.
          shown = (available / itemHeight).floor().clamp(0, itemCount);
        }
        var hidden = itemCount - shown;
        var footerHidden = hiddenCountBuilder?.call(shown) ?? hidden;
        if (footerHidden <= 0 && hidden > 0) {
          // If none of the relevant rows are hidden, reclaim the space that
          // would otherwise have been reserved for an empty footer.
          shown = (available / itemHeight).floor().clamp(0, itemCount);
          if (shown > cap) shown = cap;
          hidden = itemCount - shown;
          footerHidden = hiddenCountBuilder?.call(shown) ?? hidden;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < shown; i++)
              SizedBox(height: itemHeight, child: itemBuilder(context, i)),
            if (footerHidden > 0)
              SizedBox(
                height: footer,
                child: MoreRow(
                  hidden: footerHidden,
                  noun: noun,
                  onTap: onShowAll,
                  dense: dense,
                ),
              ),
          ],
        );
      },
    );
  }
}
