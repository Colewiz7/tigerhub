/// The scalloped badge.
///
/// The signature shape, reserved for the single most important number on a
/// card. One per card at most, which is why it takes a plain value and label
/// rather than being a general purpose container.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ScallopedBadge extends StatelessWidget {
  const ScallopedBadge({
    super.key,
    required this.value,
    this.label,
    this.size = 88,
    this.filled = true,
  });

  /// The hero number, already formatted. Short strings only.
  final String value;

  /// Small, muted caption underneath the number.
  final String? label;

  final double size;

  /// Filled uses the accent as the surface. Unfilled tints a container
  /// instead, for when the number is present but not urgent.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        filled ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = filled ? scheme.onPrimary : scheme.onSurface;

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        // Elevation is surface tint only. No shadows anywhere.
        elevation: 0,
        color: background,
        shape: Shapes.badge,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: foreground,
                      fontSize: size * 0.34,
                      // The display scale is deliberately light, but at badge
                      // size that reads as thin and washed out against the
                      // filled accent, so this one steps up.
                      fontVariations: Weights.medium,
                    ),
                maxLines: 1,
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    label!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground.withValues(alpha: 0.85),
                          fontSize: size * 0.112,
                          fontVariations: Weights.semibold,
                        ),
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
