/// Card chrome.
///
/// Surfaces nest by container level rather than by shadow: the card sits on
/// surfaceContainerLow, and anything nested inside it steps one level lighter.
/// Elevation is zero everywhere.
library;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/tokens.dart';
import 'freshness.dart';
import 'glyph.dart';

class CardShell extends StatelessWidget {
  const CardShell({
    super.key,
    required this.title,
    required this.child,
    this.state = DataState.ok,
    this.fetchedAt,
    this.hero,
    this.dragHandle,
    this.glyph,
  });

  final String title;

  /// Section identity, per the glyph-adoption spec. Only cards the spec
  /// names carry one; the rest show the title alone rather than reaching for
  /// a Material icon that means nothing.
  final GlyphKind? glyph;
  final Widget child;
  final DataState state;
  final DateTime? fetchedAt;

  /// The single most important thing on this card, shown beside the title so
  /// it costs no vertical room from the list underneath.
  final Widget? hero;

  /// The edit mode controls (drag handle, Inspect, Remove), null outside edit
  /// mode. They take their own space in the header, never an overlay.
  final Widget? dragHandle;

  /// The hero badge's width, from the spec (88px, capped text scale).
  static const double _heroWidth = 88;

  /// How many lines the title takes outside edit mode, given the whole header
  /// [width]: no controls, the glyph, and the hero if there is one.
  int _titleLines(BuildContext context, double width) {
    final room =
        width - (glyph != null ? 22 + 9 : 0) - (hero != null ? 10 + _heroWidth : 0);
    final painter = TextPainter(
      text: TextSpan(text: title, style: Theme.of(context).textTheme.titleLarge),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: room < 0 ? 0 : room);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines < 1 ? 1 : lines;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);

    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      borderRadius: Shapes.card,
      child: Padding(
        padding: const EdgeInsets.all(Insets.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, header) => Row(
              crossAxisAlignment: dragHandle == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (glyph != null) ...[
                            Glyph(glyph!, size: 22),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              title,
                              style: text.titleLarge,
                              // The edit controls narrow the title. It keeps the
                              // line count it has outside edit mode and
                              // ellipsizes past that, so edit mode never makes
                              // the card taller. The card's semantics label
                              // still carries the full name.
                              maxLines: dragHandle == null
                                  ? null
                                  : _titleLines(context, header.maxWidth),
                              overflow: dragHandle == null
                                  ? TextOverflow.clip
                                  : TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      FreshnessLine(state: state, fetchedAt: fetchedAt),
                    ],
                  ),
                ),
                // The title column is Expanded, so it wraps or ellipsizes
                // before it can reach anything on this side. In edit mode the
                // controls sit above the hero rather than beside it, which
                // keeps the title's share of the width.
                if (dragHandle != null && hero != null) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [dragHandle!, const SizedBox(height: 6), hero!],
                  ),
                ] else if (hero != null) ...[
                  const SizedBox(width: 10),
                  hero!,
                ] else if (dragHandle != null) ...[
                  const SizedBox(width: 10),
                  dragHandle!,
                ],
              ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(state == DataState.priming),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row inside a card. Separation comes from spacing, not from rules.
class RuledRow extends StatelessWidget {
  const RuledRow({super.key, required this.child, this.last = false});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: child);
}
