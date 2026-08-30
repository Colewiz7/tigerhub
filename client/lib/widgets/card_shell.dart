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

class CardShell extends StatelessWidget {
  const CardShell({
    super.key,
    required this.title,
    required this.child,
    this.state = DataState.ok,
    this.fetchedAt,
    this.hero,
    this.dragHandle,
  });

  final String title;
  final Widget child;
  final DataState state;
  final DateTime? fetchedAt;

  /// The single most important thing on this card, shown beside the title so
  /// it costs no vertical room from the list underneath.
  final Widget? hero;

  final Widget? dragHandle;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleLarge),
                      FreshnessLine(state: state, fetchedAt: fetchedAt),
                    ],
                  ),
                ),
                if (hero != null) ...[const SizedBox(width: 10), hero!],
                ?dragHandle,
              ],
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
