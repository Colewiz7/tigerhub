/// Dining card.
///
/// One hero: the scalloped badge showing occupancy for the busiest location
/// that actually has a sensor. Everything below it is plain text, so the card
/// has a single focal point rather than a row of gauges.
///
/// Every time shown is computed server side. The client displays isOpen,
/// closesAt and opensAt and does no date math.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../widgets/bounded_list.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';
import '../widgets/scalloped_badge.dart';

class DiningCard extends StatelessWidget {
  const DiningCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<DiningLocation>> result;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  /// The single location worth putting in the badge: the fullest one that
  /// publishes occupancy at all. Null when no sensor has reported.
  DiningLocation? _heroLocation(List<DiningLocation> locations) {
    final withSensor = locations
        .where((l) => l.occupancy != null && l.isOpen)
        .toList()
      ..sort((a, b) =>
          (b.occupancy!.percentFull ?? 0).compareTo(a.occupancy!.percentFull ?? 0));
    return withSensor.isEmpty ? null : withSensor.first;
  }

  @override
  Widget build(BuildContext context) {
    final locations = result.value?.data ?? const <DiningLocation>[];
    final hero = _heroLocation(locations);

    return CardShell(
      title: 'Dining',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      hero: hero == null ? null : _Hero(location: hero),
      child: switch ((result.isPriming, locations.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading dining hours'),
        (_, true) => const EmptyNote(text: 'No dining locations cached yet.'),
        _ => _List(locations: locations, onShowAll: onShowAll),
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.location});

  final DiningLocation location;

  @override
  Widget build(BuildContext context) {
    final occ = location.occupancy!;
    // A wrong denominator is never quoted as a precise figure, so an over
    // capacity reading shows the raw headcount instead of a percentage.
    final value = occ.overCapacity
        ? '${occ.count}'
        : '${occ.percentFull ?? 0}%';
    final label = occ.overCapacity ? 'HERE NOW' : 'FULL';

    return Column(
      children: [
        ScallopedBadge(value: value, label: label),
        const SizedBox(height: 8),
        Text(
          location.name,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.locations, this.onShowAll});

  final List<DiningLocation> locations;
  final VoidCallback? onShowAll;

  static const double _rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    // Open locations first, then alphabetical. Ordering only, no time math.
    final sorted = [...locations]..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return BoundedList(
      itemCount: sorted.length,
      itemHeight: _rowHeight,
      noun: 'locations',
      onShowAll: onShowAll,
      itemBuilder: (context, index) => _Row(location: sorted[index]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.location});

  final DiningLocation location;

  /// Both branches read a timestamp the API already resolved.
  String _status() {
    if (location.isOpen) {
      final closes = location.closesAt;
      return closes == null ? 'Open' : 'until ${formatClock(closes)}';
    }
    final opens = location.opensAt;
    return opens == null ? 'Closed' : 'opens ${formatClock(opens)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 11),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: location.isOpen
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        Expanded(
          child: Text(
            location.name,
            style: text.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(_status(), style: text.bodySmall, maxLines: 1),
      ],
    );
  }
}
