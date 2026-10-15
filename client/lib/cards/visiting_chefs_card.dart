/// Visiting chefs.
///
/// The chef name is the hero of each row, the location recedes beneath it.
/// Data comes straight from the TigerCenter dining payload, no separate scraper.
library;

import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/glyph.dart';
import '../widgets/freshness.dart';
import '../widgets/scalloped_badge.dart';
import '../widgets/status_row.dart';

class VisitingChefsCard extends StatelessWidget {
  const VisitingChefsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<MenuItem>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;
  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <MenuItem>[];

    return CardShell(
      // The toque is this section's identity, per the adoption spec.
      glyph: GlyphKind.visitingChef,
      title: 'Visiting Chefs',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      // This feed is already scoped to today, so its count is honest and
      // immediately useful. The individual chef name remains the hero of each
      // row; this is the one card-level number.
      hero: all.isEmpty
          ? null
          : CardHero(
              value: '${all.length}',
              label: all.length == 1 ? 'CHEF TODAY' : 'CHEFS TODAY',
              // The title already says chefs; the shorter pill keeps room for
              // the edit controls beside it on a 390 wide phone.
              pill: '${all.length} today',
            ),
      child: switch ((result.isPriming, all.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading today'),
        (_, true) => const EmptyState(
          kind: EmptyKind.noVisitingChefs,
          fill: true,
        ),
        _ => BoundedList(
          // Not capped for a compact card. A compact card is already a shorter
          // box (58% of the row height), and BoundedList measures the box it
          // is given, so a hardcoded cap of one row just stranded a single
          // chef at the top with the rest of the card empty beneath it. The
          // widget exists precisely so nobody has to guess this number.
          itemCount: all.length,
          itemHeight: StatusRow.heightFor(context, dense: true),
          dense: true,
          maxRows: phoneRowCap(context),
          noun: 'chefs',
          onShowAll: onShowAll,
          itemBuilder: (context, index) => StatusRow(
            dense: true,
            icon: Icons.restaurant_menu_rounded,
            title: all[index].name,
            subtitle: all[index].locationName,
          ),
        ),
      },
    );
  }
}
