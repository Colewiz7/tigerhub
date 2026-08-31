/// A list row as its own container.
///
/// Every dining location, event, and chef is one of these rather than a bare
/// line of text. The circular icon badge on the left is the anchor the eye
/// lands on, and the two-line title/subtitle split is what gives a row internal
/// hierarchy instead of a single flat run of words.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How prominent a row is. Dimmed rows recede without disappearing.
enum RowEmphasis { normal, dimmed }

class StatusRow extends StatelessWidget {
  const StatusRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
    this.emphasis = RowEmphasis.normal,
    this.onTap,
    this.semanticHint,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Usually a time or a chip. Kept short.
  final Widget? trailing;

  /// Tints the icon badge. Defaults to the scheme primary.
  final Color? accent;

  final RowEmphasis emphasis;
  final VoidCallback? onTap;
  final String? semanticHint;

  /// The height BoundedList should budget, including the gap beneath.
  ///
  /// Use [heightFor] wherever a BuildContext is available. This is the base
  /// figure at the system's default text size.
  static const double height = 72;

  /// [height], grown to fit the reader's text size.
  ///
  /// The row pins its title and subtitle into a fixed box so BoundedList's
  /// arithmetic stays exact. That box is sized for text at 1.0, so turning the
  /// system font up overflowed it: measured at 1.3, every list in the app
  /// spilled 6 to 7 pixels and drew the debug stripe. Android's display
  /// settings go well past 1.3, and someone who has turned text up is still
  /// holding a phone that has to work.
  ///
  /// Scaling the budget rather than shrinking the text keeps both properties:
  /// the rows still have an exact height for BoundedList to divide by, and the
  /// text is still the size the reader asked for.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Below 1 the rows would get tighter than they were designed for, and
    // above 2 a single row would eat a whole card.
    return height * scale.clamp(1.0, 2.0);
  }
  static const double gap = 8;
  static const double badgeSize = 42;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dimmed = emphasis == RowEmphasis.dimmed;
    final tint = accent ?? scheme.primary;

    // A dimmed row keeps its shape but loses contrast, so open and closed are
    // separable at a glance without reading either.
    final opacity = dimmed ? 0.55 : 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: subtitle == null ? title : '$title, $subtitle',
        hint: semanticHint,
        child: Material(
          elevation: 0,
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              // BoundedList budgets 72px including the 8px row gap. Ten
              // vertical pixels left only 44px for two text lines whose
              // configured line heights need 48, causing quiet 4px overflows
              // on longer copy. Eight preserves the touch target and gives
              // the typography its actual measured height.
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Opacity(
                    opacity: opacity,
                    child: Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Strong on purpose. Sampled from Caelestia, the badge is
                        // far brighter than the row it sits on, and that contrast is
                        // what the eye actually lands on.
                        color: tint.withValues(alpha: dimmed ? 0.20 : 0.32),
                      ),
                      // 18 in a 42px circle. At 21 the glyph very nearly filled
                      // its box, leaving a ring too thin to read as a badge.
                      child: Icon(icon, size: 18, color: tint),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Opacity(
                      opacity: opacity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    // Trailing metadata must never consume the title's entire
                    // lane on a narrow screen. Event timestamps exposed this:
                    // an unconstrained Text measured at 283px and reduced the
                    // Expanded title to zero width.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 132),
                      child: Opacity(opacity: opacity, child: trailing!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tinted header that introduces a group of rows.
///
/// Deliberately heavier than the small uppercase label it replaces: an
/// organizer name is a navigation landmark, not a footnote.
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.icon,
    required this.title,
    this.count,
  });

  final IconData icon;
  final String title;
  final int? count;

  static const double height = 46;
  static const double gap = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      child: Semantics(
        header: true,
        label: count == null ? title : '$title, $count items',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            borderRadius: Shapes.small,
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: text.titleMedium?.copyWith(color: scheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: text.titleMedium?.copyWith(
                    color: scheme.primary.withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
