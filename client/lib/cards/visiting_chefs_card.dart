/// Visiting chefs.
///
/// The chef name is the hero of each row, the time and location recede
/// beneath it. Data comes from rit.edu, with TigerCenter as a second source
/// (`data/sources/rit_chefs.dart`).
///
/// Three answers, kept apart because they mean different things: chefs today,
/// none today (a real quiet day), and unavailable (nobody could say).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/campus_time.dart';
import '../data/sources/rit_chefs.dart' show ritDiningPageUrl;
import '../widgets/empty_state.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/open_link.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/glyph.dart';
import '../widgets/freshness.dart';
import '../widgets/scalloped_badge.dart';
import '../widgets/status_row.dart';

class VisitingChefsCard extends StatelessWidget {
  const VisitingChefsCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<MenuItem>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;
  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <MenuItem>[];
    final value = result.value;
    final availability = value?.availability ?? Availability.available;
    final next = value is ChefCollection ? value.next : null;
    final updated = value?.lastUpdated ?? result.fetchedAt;

    return CardShell(
      // The toque is this section's identity, per the adoption spec.
      glyph: GlyphKind.visitingChef,
      title: 'Visiting Chefs',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      // This feed is already scoped to today, so its count is honest and
      // immediately useful. The individual chef name remains the hero of each
      // row; this is the one card-level number.
      hero: all.isEmpty
          ? null
          : ScallopedBadge(
              value: '${all.length}',
              label: all.length == 1 ? 'CHEF TODAY' : 'CHEFS TODAY',
              size: 88,
            ),
      child: switch ((result.isPriming, all.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading today'),
        (_, true) when availability == Availability.unavailable =>
          _Scrolls(
            EmptyState(
              kind: EmptyKind.sourceDown,
              title: 'Menus unavailable',
              detail: updated == null
                  ? null
                  : 'Updated ${formatAge(updated)}',
              action: const _DiningLink(),
            ),
          ),
        (_, true) => _Scrolls(
          EmptyState(
            kind: EmptyKind.noVisitingChefs,
            detail: next == null ? null : _nextLine(next),
          ),
        ),
        _ => BoundedList(
          // Not capped for a compact card. A compact card is already a shorter
          // box (58% of the row height), and BoundedList measures the box it
          // is given, so a hardcoded cap of one row just stranded a single
          // chef at the top with the rest of the card empty beneath it. The
          // widget exists precisely so nobody has to guess this number.
          itemCount: all.length,
          itemHeight: StatusRow.heightFor(context),
          noun: 'chefs',
          onShowAll: onShowAll,
          itemBuilder: (context, index) => StatusRow(
            icon: Icons.restaurant_menu_rounded,
            title: all[index].name,
            subtitle: [
              ?_window(all[index]),
              all[index].locationName,
            ].join(' · '),
          ),
        ),
      },
    );
  }

  /// "11:00 AM to 2:00 PM", on the campus clock. Null when RIT gave no time,
  /// which is never filled in by guessing.
  static String? _window(MenuItem chef) {
    final start = chef.startsAt;
    final end = chef.endsAt;
    if (start != null && end != null) {
      return '${formatClock(start)} to ${formatClock(end)}';
    }
    if (start != null) return 'from ${formatClock(start)}';
    if (end != null) return 'until ${formatClock(end)}';
    return null;
  }

  /// "Next: Thu · P.H. Express at RITZ". The date is added once the day is
  /// more than a week out, where a weekday alone would be ambiguous.
  static String _nextLine(UpcomingChef next) {
    final wall = CampusTime.wallDate();
    final today = DateTime.utc(wall.year, wall.month, wall.day);
    final days = next.date.difference(today).inDays;
    final day = days == 1
        ? 'Tomorrow'
        : DateFormat(days > 6 ? 'EEE d MMM' : 'EEE').format(next.date);
    return 'Next: $day · ${next.name} at ${next.locationName}';
  }
}

/// Lets a message taller than its box scroll instead of overflowing. At 2x
/// text a mark, a title, a detail line and a link no longer fit a compact card.
class _Scrolls extends StatelessWidget {
  const _Scrolls(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: false,
    child: SizedBox(width: double.infinity, child: child),
  );
}

/// A text link to RIT's own dining page, for when this card has nothing to
/// show. The whole 48px band is the hit area.
class _DiningLink extends StatelessWidget {
  const _DiningLink();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      link: true,
      label: 'Open RIT dining menus',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => openOrCopy(
          context,
          Uri.parse(ritDiningPageUrl),
          label: 'Link',
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(
                'RIT dining menus',
                textAlign: TextAlign.center,
                // bodyMedium, because AppTheme defines only some of the
                // scale and titleSmall is not one of them.
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
