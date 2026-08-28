/// Occupancy chip.
///
/// Only 5 of 24 dining locations publish occupancy upstream. For the other 19
/// this renders nothing at all: no placeholder, no "no data" label, no empty
/// space. The absence of a sensor is not information worth showing.
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
    if (data == null || data.percentFull == null) {
      return const SizedBox.shrink();
    }

    final percent = data.percentFull!;
    final muted = AppTheme.mutedOf(context);
    // The server clamps at 100, since the raw count can exceed max_occ.
    final fraction = (percent / 100).clamp(0.0, 1.0);

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
          '$percent% full',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
