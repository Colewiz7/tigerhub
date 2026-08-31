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
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final background = filled ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = filled ? scheme.onPrimary : scheme.onSurface;

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        // Elevation is surface tint only. No shadows anywhere.
        elevation: 0,
        color: background,
        shape: Shapes.badge,
        // The badge is a fixed geometric shape, and docs/notes.md 4 pins its
        // geometry precisely: seven points at innerRadiusRatio 0.93. Its
        // number is already the oversized one on the card. Letting the system
        // text size push that number past the shape's bounds does not make it
        // more readable, it spills it outside the scallop, which is what
        // happened at 2.0. The label beneath and the rest of the card still
        // scale normally, and the same figure is always stated in words
        // nearby, so nothing is only available inside this circle.
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3),
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: Text(
                    value,
                    key: ValueKey(value),
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
                ),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      label!,
                      // Full opacity, larger and heavier than the rest of the
                      // small caps in the app. This sits on the saturated
                      // primary rather than on a surface, and at 85% of a 10px
                      // semibold it was not readable.
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontSize: size * 0.135,
                        height: 1.1,
                        letterSpacing: 0.6,
                        fontVariations: Weights.bold,
                      ),
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
