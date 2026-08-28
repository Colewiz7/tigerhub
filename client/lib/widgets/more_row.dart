/// The "+N more" footer.
///
/// Cards live in a uniform height grid, so content is bounded explicitly
/// rather than being clipped by the layout. Nothing is ever silently cut off:
/// if relevant rows are withheld, this row says how many.
///
/// It is also the natural tap target for the detail view, so the callback is
/// wired now and currently does nothing.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class MoreRow extends StatelessWidget {
  const MoreRow({super.key, required this.hidden, this.onTap, this.noun = 'more'});

  final int hidden;
  final VoidCallback? onTap;
  final String noun;

  @override
  Widget build(BuildContext context) {
    if (hidden <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        shape: Shapes.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+$hidden $noun',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontVariations: Weights.medium,
                      ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, size: 15, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
