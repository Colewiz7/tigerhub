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
import '../widgets/card_shell.dart';
import '../widgets/glyph.dart';
import '../widgets/freshness.dart';
import '../widgets/scalloped_badge.dart';

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
    // Only a time a source really held chefs. Falling back to the fetch time
    // said "Updated just now" over a fetch that had just failed.
    final updated = value?.lastUpdated;

    // The badge and a two line title share one row, and at large text the
    // title no longer fits beside it and breaks mid word. Past this scale the
    // count moves into words beneath the title, which the spec asks for anyway.
    final badgeFits = MediaQuery.textScalerOf(context).scale(1) < _badgeScaleMax;
    final summary = '${all.length} ${all.length == 1 ? 'chef' : 'chefs'} today';

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
      hero: all.isEmpty || !badgeFits
          ? null
          : ScallopedBadge(
              value: '${all.length}',
              // One word, as the spec requires. "CHEFS TODAY" was wider than
              // the badge and wrapped over its edge. The card is today's.
              label: all.length == 1 ? 'CHEF' : 'CHEFS',
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
                  ? 'Never updated'
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
        _ => _ChefList(
          chefs: all,
          summary: badgeFits ? null : summary,
          onShowAll: onShowAll,
        ),
      },
    );
  }

  /// Text scale from which the count badge is dropped from the header.
  static const double _badgeScaleMax = 1.5;

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

/// The chefs, each row as tall as its own text needs.
///
/// A fixed row height clipped the time and location (an ellipsis after
/// "The Cafe" and half a time at 2x). Here every row wraps its lines, and the
/// rows that fit the box are chosen by measuring them, with a "+N more" pill
/// counting the rest, so nothing is cut off without being counted. If even
/// the first row and the pill cannot fit, the list scrolls rather than
/// overflowing.
class _ChefList extends StatelessWidget {
  const _ChefList({required this.chefs, this.summary, this.onShowAll});

  final List<MenuItem> chefs;

  /// The count in words, when the badge is not shown.
  final String? summary;
  final VoidCallback? onShowAll;

  static const double _gap = 8;
  static const double _badge = 42;

  static double _text(
    BuildContext context,
    String text,
    TextStyle? style,
    double width,
    int maxLines,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// The row's height, from the same styles and width it will be drawn with.
  static double _rowHeight(BuildContext context, MenuItem chef, double width) {
    final text = Theme.of(context).textTheme;
    final inner = width - 24 - _badge - 13;
    final window = VisitingChefsCard._window(chef);
    var lines = _text(context, chef.name, text.titleMedium, inner, 2);
    if (window != null) {
      lines += 2 + _text(context, window, text.bodySmall, inner, 2);
    }
    if (chef.locationName.isNotEmpty) {
      lines += 2 + _text(context, chef.locationName, text.bodySmall, inner, 3);
    }
    // 8 above and below, never shorter than the badge's own row.
    return (lines + 16 + 1).clamp(_badge + 16, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final available = constraints.maxHeight;

        final summaryHeight = summary == null
            ? 0.0
            : _text(context, summary!, text.bodyMedium, width, 1) + 10;
        final heights = [
          for (final chef in chefs) _rowHeight(context, chef, width) + _gap,
        ];
        final footer = _text(context, '+99 more', text.bodySmall, width, 1) + 12;

        var shown = chefs.length;
        if (available.isFinite) {
          final total = heights.fold<double>(summaryHeight, (a, b) => a + b);
          if (total > available) {
            shown = 0;
            var used = summaryHeight + footer + _gap;
            for (final h in heights) {
              if (used + h > available) break;
              used += h;
              shown++;
            }
          }
        }
        final hidden = chefs.length - shown;

        return _Scrolls(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    summary!,
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var i = 0; i < shown; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: _gap),
                  child: _ChefRow(chef: chefs[i]),
                ),
              if (hidden > 0) _MoreChefs(hidden: hidden, onTap: onShowAll),
            ],
          ),
        );
      },
    );
  }
}

/// One chef: a badge, the name, then the time and the location, each allowed
/// two lines.
class _ChefRow extends StatelessWidget {
  const _ChefRow({required this.chef});

  final MenuItem chef;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final window = VisitingChefsCard._window(chef);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [chef.name, ?window, chef.locationName].join(', '),
      child: Material(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        borderRadius: Shapes.inner,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: _ChefList._badge,
                height: _ChefList._badge,
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

/// "+2 more", for the chefs the box had no room for. Says "more", not "chefs",
/// so one left over never reads "+1 chefs".
class _MoreChefs extends StatelessWidget {
  const _MoreChefs({required this.hidden, this.onTap});

  final int hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: '$hidden more ${hidden == 1 ? 'chef' : 'chefs'}',
        excludeSemantics: true,
        child: Material(
          elevation: 0,
          color: scheme.surfaceContainerHigh,
          shape: Shapes.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+$hidden more',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontVariations: Weights.medium,
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
    );
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
