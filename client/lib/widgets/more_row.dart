/// The "+N more" footer.
///
/// Cards live in a uniform height grid, so content is bounded explicitly
/// rather than being clipped by the layout. Nothing is ever silently cut off:
/// if rows are withheld, this row says how many.
///
/// It is also the natural tap target for the detail view, so the callback is
/// wired now and currently does nothing.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MoreRow extends StatelessWidget {
  const MoreRow({super.key, required this.hidden, this.onTap, this.noun = 'more'});

  final int hidden;
  final VoidCallback? onTap;
  final String noun;

  @override
  Widget build(BuildContext context) {
    if (hidden <= 0) return const SizedBox.shrink();
    final muted = AppTheme.mutedOf(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Text(
              '+$hidden $noun',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: muted),
          ],
        ),
      ),
    );
  }
}
