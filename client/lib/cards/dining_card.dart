/// Dining card.
///
/// One hero, then a list of container rows. Every time shown is computed
/// server side: the client displays isOpen, closesAt and opensAt and does no
/// date math of its own.
library;

import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/semantic.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/glyph.dart';
import '../widgets/freshness.dart';
import '../services/preferences.dart';
import '../widgets/dining_detail_sheet.dart';
import '../widgets/scalloped_badge.dart';
import '../widgets/status_row.dart';

/// Sort within a category.
///
/// Only 5 of 24 locations have an occupancy sensor, so "busiest first" cannot
/// be the primary key or the other 19 land in an arbitrary order. The rule is:
/// open with a sensor first, by percent descending, then open without a sensor
/// alphabetically, then closed last.
int compareForDisplay(
  DiningLocation a,
  DiningLocation b, {
  Set<String>? pinned,
}) {
  if (pinned != null) {
    final aPinned = pinned.contains('${a.id}');
    final bPinned = pinned.contains('${b.id}');
    // A pin is an explicit statement of interest, so it outranks everything,
    // including whether the place happens to be open.
    if (aPinned != bPinned) return aPinned ? -1 : 1;
  }
  if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;

  if (a.isOpen) {
    final aHas = a.occupancy?.percentFull != null;
    final bHas = b.occupancy?.percentFull != null;
    if (aHas != bHas) return aHas ? -1 : 1;
    if (aHas && bHas) {
      final byPercent = b.occupancy!.percentFull!.compareTo(
        a.occupancy!.percentFull!,
      );
      if (byPercent != 0) return byPercent;
    }
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Group locations into the configured categories, in configured order.
List<MapEntry<String, List<DiningLocation>>> groupByCategory(
  List<DiningLocation> locations, {
  Set<String>? pinned,
}) {
  final groups = <String, List<DiningLocation>>{};
  final order = <String, int>{};
  for (final location in locations) {
    groups.putIfAbsent(location.categoryName, () => []).add(location);
    order[location.categoryName] = location.categoryOrder;
  }
  for (final entry in groups.entries) {
    entry.value.sort((a, b) => compareForDisplay(a, b, pinned: pinned));
  }
  final entries = groups.entries.toList()
    ..sort((a, b) => (order[a.key] ?? 999).compareTo(order[b.key] ?? 999));
  return entries;
}

/// Category drives the group header icon.
IconData iconForCategory(String category) => switch (category) {
  'market' => Icons.storefront_rounded,
  'global_village' => Icons.public_rounded,
  _ => Icons.restaurant_rounded,
};

/// Venue type drives the icon, so a row is identifiable before it is read.
IconData iconForVenue(String name) {
  final n = name.toLowerCase();
  if (n.contains('market') || n.contains('store') || n.contains('corner')) {
    return Icons.storefront_rounded;
  }
  if (n.contains('cafe') ||
      n.contains('café') ||
      n.contains('coffee') ||
      n.contains('beanz') ||
      n.contains('java') ||
      n.contains('grind') ||
      n.contains('oil')) {
    return Icons.local_cafe_rounded;
  }
  if (n.contains('truck')) return Icons.local_shipping_rounded;
  if (n.contains('ben') || n.contains('jerry') || n.contains('smoothie')) {
    return Icons.icecream_rounded;
  }
  return Icons.restaurant_rounded;
}

class DiningCard extends StatelessWidget {
  const DiningCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
    this.category,
    this.compact = false,
  });

  final Result<Collection<DiningLocation>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;
  final String? category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <DiningLocation>[];
    final locations = category == null
        ? all
        : [
            for (final location in all)
              if (location.category == category) location,
          ];
    final openNow = locations.where((l) => l.isOpen).length;
    final title = category == null || locations.isEmpty
        ? 'Dining'
        : locations.first.categoryName;

    return CardShell(
      glyph: GlyphKind.dining,
      title: title,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      // Card level, not location level. The hero has to answer the question
      // this card exists to answer, which is what is open right now.
      hero: locations.isEmpty
          ? null
          : ScallopedBadge(value: '$openNow', label: 'OPEN NOW', size: 88),
      child: switch ((result.isPriming, locations.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading dining hours'),
        (_, true) => const EmptyState(
          kind: EmptyKind.sourceDown,
          title: 'Dining is unavailable',
        ),
        _ => _List(
          locations: locations,
          onShowAll: onShowAll,
          limit: compact ? 1 : null,
        ),
      },
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.locations, this.onShowAll, this.limit});

  final List<DiningLocation> locations;
  final VoidCallback? onShowAll;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    // Shared ordering, so the card preview and the Dining tab agree.
    final sorted = [...locations]..sort(compareForDisplay);

    final openNow = sorted.where((location) => location.isOpen).length;

    return BoundedList(
      itemCount: limit == null ? sorted.length : sorted.length.clamp(0, limit!),
      itemHeight: StatusRow.heightFor(context),
      noun: 'open',
      // Open rows sort first, so visible capacity is consumed by open
      // locations before closed ones. The footer and the hero badge then count
      // the same population.
      hiddenCountBuilder: (shown) => (openNow - shown).clamp(0, openNow),
      onShowAll: onShowAll,
      itemBuilder: (context, index) => DiningRow(location: sorted[index]),
    );
  }
}

class DiningRow extends StatelessWidget {
  const DiningRow({super.key, required this.location, this.api});

  final DiningLocation location;

  /// When supplied the row opens a detail sheet. The Today card preview leaves
  /// it null, since tapping there navigates to the Dining tab instead.
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    final semantic = Semantic.of(context);
    final open = location.isOpen;

    // Harmonized against the wallpaper palette, never a raw hue.
    final accent = open
        ? semantic.open
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final when = open
        ? (location.closesAt == null
              ? 'OPEN · hours unavailable'
              : 'OPEN · until ${formatClock(location.closesAt!)}')
        : (location.opensAt == null
              ? 'CLOSED · hours unavailable'
              : 'CLOSED · opens ${formatDayAndClock(location.opensAt!)}');

    // A badge only when the status is NOT the default. Thirteen identical
    // green OPEN pills in a column carry no information, and they drown out
    // the five locations that actually have something to say.
    final Widget? trailing;
    if (open && location.occupancy != null) {
      // The only reason to look at the right hand column.
      trailing = _OccupancyPill(occupancy: location.occupancy!);
    } else {
      // Status is always stated in the subtitle. Only occupancy earns the
      // trailing column, so closed rows do not become a wall of red pills.
      trailing = null;
    }

    final client = api;
    return StatusRow(
      icon: Preferences.instance.isPinned(location.id)
          ? Icons.push_pin_rounded
          : iconForVenue(location.name),
      title: location.name,
      subtitle: when,
      accent: accent,
      emphasis: open ? RowEmphasis.normal : RowEmphasis.dimmed,
      onTap: client == null
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              constraints: const BoxConstraints(maxWidth: 720),
              builder: (context) =>
                  DiningDetailSheet(location: location, api: client),
            ),
      trailing: trailing,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 0,
    color: background,
    shape: const StadiumBorder(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
    ),
  );
}

class _OccupancyPill extends StatelessWidget {
  const _OccupancyPill({required this.occupancy});

  final Occupancy occupancy;

  @override
  Widget build(BuildContext context) {
    final semantic = Semantic.of(context);
    final percent = occupancy.percentFull;

    if (percent == null) {
      final count = occupancy.count;
      if (count == null) return const SizedBox.shrink();
      return _pill(
        context,
        '$count here',
        semantic.busy,
        semantic.busyContainer,
      );
    }

    // A wrong denominator is never quoted as a precise figure.
    final over = occupancy.overCapacity;
    return _pill(
      context,
      over ? 'BUSY' : '$percent%',
      over ? semantic.busy : semantic.open,
      over ? semantic.busyContainer : semantic.openContainer,
    );
  }

  Widget _pill(BuildContext context, String label, Color fg, Color bg) =>
      _StatusPill(label: label, foreground: fg, background: bg);
}
