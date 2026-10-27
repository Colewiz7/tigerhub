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
import '../theme/tokens.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/focus_ring.dart';
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

  /// Not used by this card any more. It went to the Dining tab, which lists
  /// TigerCenter specials and has none of these chefs, so "+N more" now opens
  /// a sheet of all of them instead. Kept so existing callers still compile.
  final VoidCallback? onShowAll;
  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <MenuItem>[];
    final value = result.value;
    final availability = value?.availability ?? Availability.available;

    return CardShell(
      // The toque is this section's identity, per the adoption spec.
      glyph: GlyphKind.visitingChef,
      title: 'Visiting Chefs',
      state: result.state,
      // The age of the chefs themselves, not of the request. ApiClient stamps
      // every response with the moment it arrived, which put "updated just
      // now" over a first run outage that had never held any chefs.
      fetchedAt: value?.lastUpdated,
      dragHandle: dragHandle,
      // This feed is already scoped to today, so its count is honest and
      // immediately useful. The individual chef name remains the hero of each
      // row; this is the one card-level number. It stays in the header at
      // every text size and in edit mode: a pill on a phone, the scalloped
      // badge from 600pt.
      hero: all.isEmpty
          ? null
          : CardHero(
              value: '${all.length}',
              // Main's wording, which the wide layout keeps from the base
              // commit. The title already says chefs; the shorter pill keeps
              // room for the edit controls beside it on a 390 wide phone.
              label: all.length == 1 ? 'CHEF TODAY' : 'CHEFS TODAY',
              pill: '${all.length} today',
            ),
      child: switch ((result.isPriming, all.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading today'),
        (_, true) when availability == Availability.unavailable =>
          _Centered(
            EmptyState(
              kind: EmptyKind.sourceDown,
              fill: true,
              title: 'Menus unavailable',
              action: const _DiningLink(),
            ),
          ),
        (_, true) => const _Centered(
          EmptyState(kind: EmptyKind.noVisitingChefs, fill: true),
        ),
        _ => BoundedList(
          itemCount: all.length,
          itemHeight: StatusRow.heightFor(context, dense: true),
          dense: true,
          maxRows: phoneRowCap(context),
          // "+2 more", not "+2 chefs": one left over never reads "+1 chefs".
          noun: 'more',
          // The Dining tab lists TigerCenter specials and has none of these
          // chefs, so "+N more" opens a sheet of all of them. [onShowAll] is
          // accepted for existing callers and unused.
          onShowAll: () => _showAllChefs(context, all),
          itemBuilder: (context, index) => StatusRow(
            dense: true,
            icon: Icons.restaurant_menu_rounded,
            title: all[index].name,
            subtitle: [
              ?_window(all[index]),
              all[index].locationName,
            ].where((s) => s.isNotEmpty).join(' · '),
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
      return '${_clock(start)} to ${_clock(end)}';
    }
    if (start != null) return 'from ${_clock(start)}';
    if (end != null) return 'until ${_clock(end)}';
    return null;
  }

  /// "11 AM" on the hour and "4:30 PM" otherwise. The ":00" is dropped because
  /// at large text it is what pushed the window onto a second line.
  static String _clock(DateTime when) {
    final f = CampusTime.fieldsOf(when);
    if (f.minute == 0 && f.hour != 0 && f.hour != 12) {
      return DateFormat('h a').format(f);
    }
    return formatClock(when);
  }

}

/// One chef: a badge, the name, then the time and the location, each allowed
/// two lines.
class _ChefRow extends StatelessWidget {
  const _ChefRow({required this.chef, this.showCuisine = false});

  final MenuItem chef;

  /// The card has no room for the cuisine. The sheet that lists every chef does.
  final bool showCuisine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final window = VisitingChefsCard._window(chef);
    final cuisine = showCuisine ? chef.cuisine : null;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        chef.name,
        ?window,
        if (chef.locationName.isNotEmpty) chef.locationName,
        ?cuisine,
      ].join(', '),
      child: Material(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        borderRadius: Shapes.inner,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: StatusRow.badgeSize,
                height: StatusRow.badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.32),
                ),
                child: Icon(
                  Icons.restaurant_menu_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chef.name,
                      style: text.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (window != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        window,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (chef.locationName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        chef.locationName,
                        style: text.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (cuisine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        cuisine,
                        style: text.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every chef, in a modal bottom sheet. A sheet rather than an inline expand
/// because the card has a fixed box in a grid of cards, and growing it would
/// push the rest of the home screen about. Esc, the scrim and the close button
/// all dismiss it.
Future<void> _showAllChefs(BuildContext context, List<MenuItem> chefs) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: scheme.surfaceContainerLow,
    barrierColor: scheme.surfaceContainerLowest.withValues(alpha: 0.6),
    // Under 600pt the spec's project override wins: card radius 24, not 30.
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(
          MediaQuery.sizeOf(context).width < 600 ? 24 : Shapes.cardRadius,
        ),
      ),
    ),
    builder: (context) => _ChefsSheet(chefs: chefs),
  );
}

class _ChefsSheet extends StatelessWidget {
  const _ChefsSheet({required this.chefs});

  final List<MenuItem> chefs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.cardPadding, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '${chefs.length} visiting '
                      '${chefs.length == 1 ? 'chef' : 'chefs'} today',
                      style: text.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                Insets.cardPadding,
                4,
                Insets.cardPadding,
                Insets.cardPadding,
              ),
              shrinkWrap: true,
              itemCount: chefs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _ChefRow(chef: chefs[index], showCuisine: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty or unavailable message, centered in the box the card gives it at
/// every text size, and scrolling rather than overflowing when a mark, a
/// title, a detail line and a link are taller than that box (2x text).
class _Centered extends StatelessWidget {
  const _Centered(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (!box.maxHeight.isFinite) return child;
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        primary: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(child: child),
        ),
      );
    },
  );
}

/// A text link to RIT's own dining page, for when this card has nothing to
/// show. The whole 48px band is the hit area.
class _DiningLink extends StatelessWidget {
  const _DiningLink();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void open() =>
        openOrCopy(context, Uri.parse(ritDiningPageUrl), label: 'Link');
    // excludeSemantics drops the InkWell's own tap action, so the link
    // carries it here or a screen reader could not follow it.
    return Semantics(
      link: true,
      label: 'View on RIT',
      onTap: open,
      excludeSemantics: true,
      child: FocusRing(
        radius: 24,
        builder: (onFocusChange) => InkWell(
          borderRadius: BorderRadius.circular(24),
          onFocusChange: onFocusChange,
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'View on RIT',
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
      ),
    );
  }
}
