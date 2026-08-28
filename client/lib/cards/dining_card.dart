/// Dining card.
///
/// Every time shown here is computed server side. The client displays
/// `isOpen`, `closesAt`, and `nextTransition` and does no date math of its own.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/card_shell.dart';
import '../widgets/freshness.dart';
import '../widgets/bounded_list.dart';
import '../widgets/occupancy_chip.dart';

class DiningCard extends StatelessWidget {
  const DiningCard({
    super.key,
    required this.result,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<DiningLocation>> result;
  final Widget? dragHandle;

  /// Tap target for the detail view. Not built yet, so this is a no-op.
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final collection = result.value;

    return CardShell(
      title: 'Dining',
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      child: switch ((result.isPriming, collection?.data.isEmpty ?? true)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading dining hours'),
        (_, true) => const EmptyNote(text: 'No dining locations cached yet.'),
        _ => _List(locations: collection!.data, onShowAll: onShowAll),
      },
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.locations, this.onShowAll});

  final List<DiningLocation> locations;
  final VoidCallback? onShowAll;

  /// Enforced row height, so BoundedList can do exact arithmetic.
  static const double _rowHeight = 62;

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
      itemBuilder: (context, index) => RuledRow(
        last: index == sorted.length - 1,
        child: _Row(location: sorted[index]),
      ),
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
      return closes == null ? 'Open' : 'Open until ${formatClock(closes)}';
    }
    final opens = location.opensAt;
    return opens == null ? 'Closed' : 'Closed, opens ${formatDayAndClock(opens)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: location.isOpen ? AppTheme.accent : AppTheme.ruleOf(context),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location.name,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _status(),
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Renders nothing for the 19 locations without a sensor.
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2),
          child: OccupancyChip(occupancy: location.occupancy),
        ),
      ],
    );
  }
}
