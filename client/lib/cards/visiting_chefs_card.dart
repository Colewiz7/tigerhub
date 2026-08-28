/// Visiting chefs, straight from the TigerCenter dining payload.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';

class VisitingChefsCard extends StatelessWidget {
  const VisitingChefsCard({super.key, required this.result, this.dragHandle});

  final Result<Collection<MenuItem>> result;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final items = result.value?.data ?? const <MenuItem>[];
    final text = Theme.of(context).textTheme;

    return CardShell(
      title: 'Visiting Chefs',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      child: switch ((result.isPriming, items.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading today'),
        (_, true) => const EmptyNote(text: 'No visiting chefs on campus today.'),
        _ => ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return RuledRow(
                last: index == items.length - 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(item.locationName, style: text.bodySmall),
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.description!, style: text.bodySmall),
                    ],
                  ],
                ),
              );
            },
          ),
      },
    );
  }
}
