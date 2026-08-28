/// Occupancy chip, a full pill.
///
/// Only 5 of 24 dining locations publish occupancy upstream. For the other 19
/// this renders nothing at all: no placeholder, no "no data" label.
///
/// Honesty rules:
///  - `overCapacity` means the count exceeds RIT's published capacity, which
///    is common. The denominator is wrong, so a qualitative "busy" is shown
///    rather than a precise looking percentage.
///  - No denominator at all yields the raw count, labelled as a count.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import 'segmented_bar.dart';

class OccupancyChip extends StatelessWidget {
  const OccupancyChip({super.key, required this.occupancy});

  final Occupancy? occupancy;

  @override
  Widget build(BuildContext context) {
    final data = occupancy;
    if (data == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final percent = data.percentFull;

    if (percent == null) {
      if (data.count == null) return const SizedBox.shrink();
      return _Pill(child: Text('${data.count} here', style: text.bodySmall));
    }

    final label = data.overCapacity ? 'busy' : '$percent%';
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedBar(value: percent / 100, width: 34, height: 4, gap: 3),
          const SizedBox(width: 7),
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: child,
        ),
      );
}
