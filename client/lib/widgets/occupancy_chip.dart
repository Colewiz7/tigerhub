/// Occupancy chip.
///
/// Only 5 of 24 dining locations publish occupancy upstream. For the other 19
/// this renders nothing at all: no placeholder, no "no data" label, no empty
/// space. The absence of a sensor is not information worth showing.
///
/// Honesty rules for what is shown:
///  - `over_capacity` means the live count exceeds RIT's published capacity,
///    which happens often (Midnight Oil reads 46 against a stated 38). The
///    denominator is clearly wrong, so a qualitative "busy" is shown rather
///    than a precise looking "100% full".
///  - No denominator at all yields the raw count, labelled as a count, rather
///    than the location being silently dropped.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../theme/app_theme.dart';

class OccupancyChip extends StatelessWidget {
  const OccupancyChip({super.key, required this.occupancy});

  final Occupancy? occupancy;

  @override
  Widget build(BuildContext context) {
    final data = occupancy;
    if (data == null) return const SizedBox.shrink();

    final percent = data.percentFull;
    final muted = AppTheme.mutedOf(context);

    // A count with no usable capacity. Say what it is, do not imply a ratio.
    if (percent == null) {
      if (data.count == null) return const SizedBox.shrink();
      return Text(
        '${data.count} here now',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
      );
    }

    // The bar is a rough fill indicator in both cases.
    final fraction = (percent / 100).clamp(0.0, 1.0);
    final label = data.overCapacity ? 'busy' : '$percent% full';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 34,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppTheme.ruleOf(context)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: AppTheme.accent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
