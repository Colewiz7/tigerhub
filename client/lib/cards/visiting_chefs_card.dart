/// Visiting chefs.
///
/// The chef name is the hero of each row, the location recedes beneath it.
/// Data comes straight from the TigerCenter dining payload, no separate scraper.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';
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
      title: 'Visiting Chefs',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      child: switch ((result.isPriming, all.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading today'),
        (_, true) => const EmptyNote(text: 'No visiting chefs on campus today.'),
        _ => BoundedList(
            itemCount: all.length,
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
