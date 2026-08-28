/// Visiting chefs, straight from the TigerCenter dining payload.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';
import '../widgets/bounded_list.dart';

class VisitingChefsCard extends StatelessWidget {
  const VisitingChefsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<MenuItem>> result;
  final Widget? dragHandle;

  /// Tap target for the detail view. Not built yet, so this is a no-op.
  final VoidCallback? onShowAll;

  static const double _rowHeight = 62;

  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <MenuItem>[];
    final text = Theme.of(context).textTheme;

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
            itemHeight: _rowHeight,
            noun: 'chefs',
            onShowAll: onShowAll,
            itemBuilder: (context, index) => RuledRow(
              last: index == all.length - 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    all[index].name,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    all[index].locationName,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
      },
    );
  }
}
