/// Every place of one kind, grouped by building.
///
/// The official map makes "where is the nearest water fountain" surprisingly
/// hard: you have to know which category it lives under and then hunt on a map.
/// This is the same data as a searchable list, grouped by building, because
/// people navigate campus by building, not by coordinate.
library;

import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';
import '../services/subscriptions.dart';

class PlacesSheet extends StatefulWidget {
  const PlacesSheet({
    super.key,
    required this.api,
    required this.kind,
    required this.title,
    required this.icon,
  });

  final ApiClient api;
  final String kind;
  final String title;
  final IconData icon;

  @override
  State<PlacesSheet> createState() => _PlacesSheetState();
}

class _PlacesSheetState extends State<PlacesSheet> {
  Result<Collection<CampusPlace>>? _result;
  String _query = '';

  /// Held so they can be cancelled. Dangling subscriptions let a previous
  /// visit's results land after the current ones and overwrite them.
  final _subscriptions = Subscriptions();

  @override
  void initState() {
    super.initState();
    _subscriptions.add(widget.api.places(widget.kind).listen((r) {
      if (mounted) setState(() => _result = r);
    }));
  }

  @override
  void dispose() {
    _subscriptions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final all = _result?.value?.data ?? const <CampusPlace>[];

    final matches = _query.isEmpty
        ? all
        : all.where((p) {
            final q = _query.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                (p.building ?? '').toLowerCase().contains(q) ||
                (p.note ?? '').toLowerCase().contains(q);
          }).toList();

    // People navigate by building.
    final byBuilding = <String, List<CampusPlace>>{};
    for (final place in matches) {
      byBuilding.putIfAbsent(place.building ?? 'Elsewhere', () => []).add(place);
    }
    final buildings = byBuilding.keys.toList()..sort();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(widget.icon,
                    size: 22, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(widget.title,
                    style: text.titleLarge?.copyWith(fontSize: 22)),
                const Spacer(),
                Text('${all.length}', style: text.labelSmall),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Filter by building or description',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            if (_result?.isPriming ?? true)
              const PrimingPlaceholder(label: 'Loading')
            else if (matches.isEmpty)
              const EmptyState(kind: EmptyKind.notFound, compact: false)
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: buildings.length,
                  itemBuilder: (context, index) {
                    final building = buildings[index];
                    final places = byBuilding[building]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GroupHeader(
                            icon: Icons.apartment_rounded,
                            title: building,
                            count: places.length,
                          ),
                          for (final place in places)
                            _PlaceRow(place: place),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place});

  final CampusPlace place;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.where.isEmpty ? place.name : place.where,
                style: text.titleMedium),
            if (place.note != null) ...[
              const SizedBox(height: 3),
              Text(place.note!, style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Icon per kind. Falls back rather than guessing wrong.
IconData iconForPlaceKind(String kind) => switch (kind) {
      'water' => Icons.water_drop_rounded,
      'blue_light' => Icons.emergency_rounded,
      'aed' => Icons.monitor_heart_rounded,
      'restroom_all_gender' => Icons.wc_rounded,
      'restroom_accessible' => Icons.accessible_rounded,
      'entrance_accessible' => Icons.door_front_door_rounded,
      'atm' => Icons.local_atm_rounded,
      'bus_stop' => Icons.directions_bus_rounded,
      'bike_rack' => Icons.pedal_bike_rounded,
      'ev_charge' => Icons.ev_station_rounded,
      'reload' => Icons.credit_card_rounded,
      'changing_table' => Icons.baby_changing_station_rounded,
      _ => Icons.place_rounded,
    };
