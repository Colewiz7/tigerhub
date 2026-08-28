/// Dining tab: every location, grouped by category.
///
/// Categories come from the server's static config, because TigerCenter
/// publishes none of its own (catId, mapId and mrkId are 0 on all 24, and
/// department is "Dining" for every one).
library;

import 'package:flutter/material.dart';

import '../cards/dining_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/content_column.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';

class DiningScreen extends StatelessWidget {
  const DiningScreen({super.key, required this.result});

  final Result<Collection<DiningLocation>> result;

  @override
  Widget build(BuildContext context) {
    if (result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading dining hours');
    }

    final groups = groupByCategory(result.value?.data ?? const []);

    return ContentColumn(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          final openInGroup = group.value.where((l) => l.isOpen).length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GroupHeader(
                  icon: iconForCategory(group.value.first.category),
                  title: group.key,
                  count: openInGroup,
                ),
                for (final location in group.value)
                  DiningRow(location: location),
              ],
            ),
          );
        },
      ),
    );
  }
}
