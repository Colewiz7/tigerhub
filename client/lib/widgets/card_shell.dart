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

/// Width of the edit controls row: handle, Inspect and Remove at 32 each with
/// 6 between. The title's line budget depends on it.
const double editControlsWidth = 32 * 3 + 6 * 2;

/// Room a hero leaves the title in edit mode before the hero scales down.
const double _minEditTitleWidth = 48;

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

  /// Section identity, per `docs/glyph-adoption-spec.md`. Only cards the spec
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

  /// How many lines the title takes outside edit mode. [editWidth] is the room
  /// the title column has in edit mode, after the real hero and the controls
  /// have taken theirs, so adding the controls' slot back gives the room it has
  /// outside edit mode, whatever the hero is.
  int _titleLines(BuildContext context, double editWidth) {
    final room = editWidth + 10 + editControlsWidth - (glyph != null ? 22 + 9 : 0);
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Expanded, so the title wraps or ellipsizes before it can
                // reach the hero or the edit controls on its right.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, titleBox) => Column(
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
                                // The edit controls take room beside the
                                // hero, so the title keeps the line count it
                                // has outside edit mode and ellipsizes past
                                // that. Edit mode then never makes the header,
                                // or the card, taller. The ellipsis is only
                                // visual: the Text still holds the full title.
                                maxLines: dragHandle == null
                                    ? null
                                    : _titleLines(context, titleBox.maxWidth),
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
                ),
                // The hero keeps its slot, and the controls sit after it in
                // the same row band, so nothing here can overlap.
                // Wrapped the same way in both modes, so toggling edit mode
                // does not rebuild the hero and replay its entrance. Only in
                // edit mode is it capped, and only a very wide hero (a text
                // one at large text) ever scales down, so it never overflows
                // the row or hides.
                if (hero != null) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: dragHandle == null
                          ? double.infinity
                          : (header.maxWidth -
                                    20 -
                                    editControlsWidth -
                                    _minEditTitleWidth)
                                .clamp(0, double.infinity),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: hero!,
                    ),
                  ),
                ],
                if (dragHandle != null) ...[
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
