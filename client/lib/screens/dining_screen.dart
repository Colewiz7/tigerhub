/// Dining tab: every location, not just the bounded card preview.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/freshness.dart';
import '../widgets/occupancy_chip.dart';
import '../theme/tokens.dart';

class DiningScreen extends StatelessWidget {
  const DiningScreen({super.key, required this.result});

  final Result<Collection<DiningLocation>> result;

  @override
  Widget build(BuildContext context) {
    final locations = [...(result.value?.data ?? const <DiningLocation>[])]
      ..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    if (result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading dining hours');
    }

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      itemCount: locations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final location = locations[index];
        return Material(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          borderRadius: Shapes.inner,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: location.isOpen
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(location.name, style: text.bodyMedium, maxLines: 1),
                      const SizedBox(height: 2),
                      Text(
                        location.isOpen
                            ? (location.closesAt == null
                                ? 'Open'
                                : 'until ${formatClock(location.closesAt!)}')
                            : (location.opensAt == null
                                ? 'Closed'
                                : 'opens ${formatDayAndClock(location.opensAt!)}'),
                        style: text.bodySmall,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OccupancyChip(occupancy: location.occupancy),
              ],
            ),
          ),
        );
      },
    );
  }
}
