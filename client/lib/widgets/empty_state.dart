/// Themed empty states.
///
/// Empty is the normal state here, not an edge case. Visiting chefs is empty
/// most days, an event list empties as soon as organizers are muted, and at
/// night every dining category is closed. Before this they were all a single
/// line of grey text in an otherwise blank card.
///
/// **Offline and source-down are status states, not loaders.** The spec is
/// explicit and it matches the project notes 3.1: cached content stays at full opacity
/// and one of these sits beside it. Neither ever replaces data the app already
/// holds.
library;

import 'package:flutter/material.dart';

/// Each state uses a familiar symbol inside the same restrained circular badge
/// language as the rest of the app. Empty states used to render cartoon tiger
/// scenes, which made ordinary "nothing today" results feel like novelty art.
enum EmptyKind {
  noEvents(Icons.event_busy_rounded, 'No events today'),
  allClosed(Icons.nightlight_round, 'All closed'),
  noVisitingChefs(Icons.room_service_rounded, 'No visiting chefs today'),
  notFound(Icons.search_off_rounded, 'No matches'),
  offline(Icons.cloud_off_rounded, 'Showing saved data'),
  sourceDown(Icons.sync_problem_rounded, 'Unavailable');

  const EmptyKind(this.icon, this.title);

  final IconData icon;

  /// The default line. Callers may override it where they can say something
  /// more specific, but the wording should stay this plain.
  final String title;
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.kind,
    this.title,
    this.action,
    this.compact = true,
    this.fill = false,
  });

  /// Take all the height offered and center in it. The Visiting Chefs card sets
  /// it: its empty card fills its cell on wide layouts, as it always has.
  final bool fill;

  final EmptyKind kind;

  /// Overrides [EmptyKind.title] when the caller can be more specific.
  final String? title;

  /// An optional action. There is no body text: a title and an icon only.
  final Widget? action;

  /// Cards use a smaller mark than full panels.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final markSize = compact ? 58.0 : 76.0;

    // Takes the room it is given across and centers in it. A card's content
    // column is left aligned, so without this the mark and sentence sat at the
    // left edge. With no bounded width (a list, a scroll view) it just takes its
    // own size. With [fill] it also takes the height it is given, so it centers
    // down a fixed height cell; without, the card is as tall as the block.
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: box.maxWidth.isFinite ? box.maxWidth : null,
        height: fill && box.maxHeight.isFinite ? box.maxHeight : null,
        // heightFactor 1: a Center would otherwise take all the height offered.
        child: Center(
          heightFactor: 1,
          child: _body(context, text, scheme, markSize),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    TextTheme text,
    ColorScheme scheme,
    double markSize,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: markSize,
              height: markSize,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                kind.icon,
                size: compact ? 29 : 38,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title ?? kind.title,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
