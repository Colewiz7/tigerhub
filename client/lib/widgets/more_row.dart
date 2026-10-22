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
import 'focus_ring.dart';
import 'touch_target.dart';

class MoreRow extends StatelessWidget {
  const MoreRow({
    super.key,
    required this.hidden,
    this.onTap,
    this.noun = 'more',
    this.dense = false,
  });

  final int hidden;
  final VoidCallback? onTap;
  final String noun;

  /// The phone dashboard's footer: one text row, "+10 open ›", with no pill.
  final bool dense;

  /// The text row's visual height. Its hit region is [TouchTarget.size].
  static const double denseHeight = 28;

  @override
  Widget build(BuildContext context) {
    if (hidden <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    if (dense && Insets.phone(context)) {
      // A 28 visual row inside a 48 tall hit region.
      return TouchTarget(
        alignment: Alignment.centerLeft,
        onTap: onTap,
        child: Semantics(
          button: onTap != null,
          enabled: onTap != null,
          label: _label,
          child: FocusRing(
            radius: Shapes.smallRadius,
            builder: (onFocusChange) => InkWell(
              onTap: onTap,
              onFocusChange: onFocusChange,
              borderRadius: Shapes.small,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: denseHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The label above already says it. Left in, the visible
                      // text merges in and it reads twice.
                      ExcludeSemantics(
                        child: Text(
                          '+$hidden $noun',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: muted,
                                fontSize: 14,
                                letterSpacing: 0,
                                fontVariations: Weights.medium,
                              ),
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: muted,
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

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: _label,
        child: FocusRing(
          radius: 24,
          builder: (onFocusChange) => Material(
            elevation: 0,
            color: scheme.surfaceContainerHigh,
            shape: Shapes.pill,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onFocusChange: onFocusChange,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        '+$hidden $noun',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontVariations: Weights.medium,
                        ),
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.chevron_right_rounded, size: 15, color: muted),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "+2 more events", or just "+2 more" when the noun is the default, which
  /// is the visible footer text.
  String get _label => noun == 'more' ? '+$hidden more' : '+$hidden more $noun';
}
