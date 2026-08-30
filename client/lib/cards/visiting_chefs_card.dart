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
    this.compact = false,
  });

  final Result<Collection<MenuItem>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;
  final bool compact;

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
          : ScallopedBadge(
              value: '${all.length}',
              label: all.length == 1 ? 'CHEF TODAY' : 'CHEFS TODAY',
              size: 88,
            ),
      child: switch ((result.isPriming, all.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading today'),
        (_, true) => const EmptyState(kind: EmptyKind.noVisitingChefs),
        _ => BoundedList(
          itemCount: compact ? 1 : all.length,
          itemHeight: StatusRow.height,
          noun: 'chefs',
          onShowAll: onShowAll,
          itemBuilder: (context, index) => StatusRow(
            icon: Icons.restaurant_menu_rounded,
            title: all[index].name,
            subtitle: all[index].locationName,
          ),
        ),
      },
    );
  }
}
