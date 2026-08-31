/// The "N hidden" footer.
///
/// Nothing filtered is ever silently gone. Every filtered view ends with a
/// count that expands to reveal the hidden rows dimmed in place, so a thing
/// that moved to a different organizer is still findable.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class HiddenFooter extends StatelessWidget {
  const HiddenFooter({
    super.key,
    required this.count,
    required this.expanded,
    required this.onToggle,
    this.noun = 'hidden',
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final String noun;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          expanded: expanded,
          label: expanded ? 'Hide $count $noun' : 'Show $count $noun',
          child: Material(
            elevation: 0,
            color: scheme.surfaceContainerHigh,
            shape: Shapes.pill,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expanded
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      expanded ? 'Hide $count again' : '$count $noun',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        fontVariations: Weights.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
