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
import '../theme/tokens.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/app_icon.dart';
import '../widgets/freshness.dart';
import '../services/preferences.dart';
import '../widgets/dining_actions.dart';
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

/// Eat now on a phone: your open spots, then other open places, then your
/// closed spots, which only reach the card when rows are left over.
List<DiningLocation> eatNowOrder(List<DiningLocation> locations, Set<String> pinned) {
  bool isPinned(DiningLocation l) => pinned.contains('${l.id}');
  List<DiningLocation> sorted(bool Function(DiningLocation) test) =>
      [...locations.where(test)]..sort(compareForDisplay);
  return [
    ...sorted((l) => l.isOpen && isPinned(l)),
    ...sorted((l) => l.isOpen && !isPinned(l)),
    ...sorted((l) => !l.isOpen && isPinned(l)),
  ];
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
AppIconKind iconForCategory(String category) => switch (category) {
  'market' => AppIconKind.market,
  'global_village' => AppIconKind.globe,
  _ => AppIconKind.dining,
};

/// Venue type drives the icon, so a row is identifiable before it is read.
AppIconKind iconForVenue(String name) {
  final n = name.toLowerCase().replaceAll('’', "'");
  for (final (needles, kind) in _venueIcons) {
    if (needles.any(n.contains)) return kind;
  }
  return AppIconKind.dining;
}

// first match wins, crossroads and artesano say cafe too
const _venueIcons = [
  (['gracie', 'commons', 'brick city', 'ritz', 'crossroads'], AppIconKind.diningHall),
  (['artesano', 'bakery'], AppIconKind.bakery),
  (['jerry'], AppIconKind.iceCream),
  (['usb', 'smoothie'], AppIconKind.smoothie),
  (['deli'], AppIconKind.deli),
  (['loaded latke', 'petals', 'gpc'], AppIconKind.restaurant),
  (['nathan', 'soup'], AppIconKind.soup),
  (['patio'], AppIconKind.patio),
  (['beanz', 'grind', 'java', 'midnight oil', 'cafe', 'café', 'coffee'], AppIconKind.cafe),
  (['corner store', 'bytes', 'market', "sol's", 'store'], AppIconKind.grocery),
  (['truck'], AppIconKind.truck),
  (['dining office'], AppIconKind.diningOffice),
];

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Preferences.instance,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final hiddenIds = Preferences.instance.hiddenDining;
    final all = [
      for (final l in result.value?.data ?? const <DiningLocation>[])
        if (!hiddenIds.contains('${l.id}')) l,
    ];
    final locations = category == null
        ? all
        : [
            for (final location in all)
              if (location.category == category) location,
          ];
    final openNow = locations.where((l) => l.isOpen).length;
    // the phone card answers one question, wide keeps its name
    final title = category == null || locations.isEmpty
        ? (Insets.phone(context) ? 'Eat now' : 'Dining')
        : locations.first.categoryName;

    return CardShell(
      glyph: AppIconKind.dining,
      title: title,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      onOpen: onShowAll,
      openLabel: 'opens Dining',
      // Card level, not location level. The hero has to answer the question
      // this card exists to answer, which is what is open right now.
      hero: locations.isEmpty
          ? null
          : CardHero(value: '$openNow', label: 'Open'),
      child: switch ((result.isPriming, locations.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading dining hours'),
        (_, true) => EmptyState(
          kind: all.isEmpty && (result.value?.data.isNotEmpty ?? false) ? EmptyKind.notFound : EmptyKind.sourceDown,
          title: all.isEmpty && (result.value?.data.isNotEmpty ?? false) ? 'No places' : 'Dining unavailable',
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Preferences.instance,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    // Shared ordering, so the card preview and the Dining tab agree.
    final pinned = Preferences.instance.pinnedDining;
    final sorted = Insets.phone(context)
        ? eatNowOrder(locations, pinned)
        : ([...locations]..sort((a, b) => compareForDisplay(a, b, pinned: pinned)));
    if (sorted.isEmpty) {
      return const EmptyState(kind: EmptyKind.allClosed);
    }

    return BoundedList(
      itemCount: limit == null ? sorted.length : sorted.length.clamp(0, limit!),
      itemHeight: StatusRow.heightFor(context, dense: true),
      dense: true,
      maxRows: phoneRowCap(context),
      noun: 'open',
      // The footer counts open places left out, so it matches the hero badge
      // even when a closed pin takes a row.
      hiddenCountBuilder: (shown) =>
          sorted.skip(shown).where((location) => location.isOpen).length,
      onShowAll: onShowAll,
      itemBuilder: (context, index) =>
          DiningRow(location: sorted[index], dense: true),
    );
  }
}

class DiningRow extends StatelessWidget {
  const DiningRow({
    super.key,
    required this.location,
    this.api,
    this.dense = false,
  });

  final DiningLocation location;

  /// The dashboard's condensed phone row.
  final bool dense;

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
              ? 'Open · hours unavailable'
              : 'Open · until ${formatClock(location.closesAt!)}')
        : (location.opensAt == null
              ? 'Closed · hours unavailable'
              : 'Closed · opens ${formatDayAndClock(location.opensAt!)}');

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
      dense: dense,
      icon: Preferences.instance.isPinned(location.id)
          ? AppIconKind.pinned
          : iconForVenue(location.name),
      title: location.name,
      subtitle: when,
      accent: accent,
      emphasis: open ? RowEmphasis.normal : RowEmphasis.quiet,
      onTap: client == null
          ? null
          : () => DiningDetailPage.open(context, location, client),
      trailing: trailing,
      // the Today card previews, so only the tab carries the menu
      actions: client == null ? const [] : diningActions(location),
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
        // no tracking, so "50% full" leaves the name its one line
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, letterSpacing: 0),
      ),
    ),
  );
}

/// Below this a sensor reading says Quiet, not a small percent.
const int quietBelowPercent = 15;

/// The occupancy pill's words: Busy over capacity, Quiet under 15% full,
/// otherwise "N% full". Null with no percent reading.
String? occupancyLabel(Occupancy occupancy) {
  final percent = occupancy.percentFull;
  if (percent == null) return null;
  if (occupancy.overCapacity) return 'Busy';
  if (percent < quietBelowPercent) return 'Quiet';
  return '$percent% full';
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
      occupancyLabel(occupancy)!,
      over ? semantic.busy : semantic.open,
      over ? semantic.busyContainer : semantic.openContainer,
    );
  }

  Widget _pill(BuildContext context, String label, Color fg, Color bg) =>
      _StatusPill(label: label, foreground: fg, background: bg);
}
