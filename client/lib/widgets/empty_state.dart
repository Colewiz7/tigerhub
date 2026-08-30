/// Illustrated empty states.
///
/// Empty is the normal state here, not an edge case. Visiting chefs is empty
/// most days, an event list empties as soon as organizers are muted, and at
/// night every dining category is closed. Before this they were all a single
/// line of grey text in an otherwise blank card.
///
/// Art from Codex, spec in `assets/generated/SPEC.md`: 200x140 canvas, shown at
/// 112x78 in a card and up to full size in a panel, 20px between illustration
/// and copy.
///
/// **Offline and source-down are status states, not loaders.** The spec is
/// explicit and it matches CLAUDE.md 3.1: cached content stays at full opacity
/// and one of these sits beside it. Neither ever replaces data the app already
/// holds.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The states Codex drew, paired with the copy from the spec.
enum EmptyKind {
  noEvents('no-events', 'Nothing scheduled today'),
  allClosed('all-closed', 'Everything is closed right now'),
  noVisitingChefs('no-visiting-chefs', 'No visiting chefs today'),
  notFound('not-found', 'No matches'),
  offline('offline', 'Showing saved data'),
  sourceDown('source-down', 'This source is unavailable');

  const EmptyKind(this.asset, this.title);

  final String asset;

  /// The default line. Callers may override it where they can say something
  /// more specific, but the wording should stay this plain.
  final String title;

  String get path => 'assets/generated/empty-states/$asset.svg';
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

  /// Cards are tight on space, so the illustration is shown at 112x78 there
  /// and at full size in a panel that has room for it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final width = compact ? 112.0 : 200.0;
    final height = compact ? 78.0 : 140.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Semantics comes from the label below, so the art is hidden from
          // screen readers rather than announced twice.
          ExcludeSemantics(
            child: SvgPicture.asset(
              kind.path,
              width: width,
              height: height,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title ?? kind.title,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 8),
            action!,
          ],
        ],
      ),
    );
  }
}
