/// Themed empty states.
///
/// Empty is the normal state here, not an edge case. Visiting chefs is empty
/// most days, an event list empties as soon as organizers are muted, and at
/// night every dining category is closed. Before this they were all a single
/// line of grey text in an otherwise blank card.
///
/// **Offline and source-down are status states, not loaders.** The spec is
/// explicit and it matches docs/notes.md 3.1: cached content stays at full opacity
/// and one of these sits beside it. Neither ever replaces data the app already
/// holds.
library;

import 'package:flutter/material.dart';

/// Each state uses a familiar symbol inside the same restrained circular badge
/// language as the rest of the app. Empty states used to render cartoon tiger
/// scenes, which made ordinary "nothing today" results feel like novelty art.
enum EmptyKind {
  noEvents(Icons.event_busy_rounded, 'Nothing scheduled today'),
  allClosed(Icons.nightlight_round, 'Everything is closed right now'),
  noVisitingChefs(Icons.room_service_rounded, 'No visiting chefs today'),
  notFound(Icons.search_off_rounded, 'No matches'),
  offline(Icons.cloud_off_rounded, 'Showing saved data'),
  sourceDown(Icons.sync_problem_rounded, 'This source is unavailable');

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
    this.detail,
    this.action,
    this.compact = true,
  });

  final EmptyKind kind;

  /// Overrides [EmptyKind.title] when the caller can be more specific.
  final String? title;

  /// One optional supporting line. Keep it short, and do not apologise.
  final String? detail;

  final Widget? action;

  /// Cards use a smaller mark than full panels.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final markSize = compact ? 58.0 : 76.0;

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
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center, style: text.bodySmall),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
