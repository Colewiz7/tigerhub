library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/semantic.dart';
import '../widgets/campus_map.dart';
import '../widgets/card_shell.dart';
import '../widgets/empty_state.dart';
import '../widgets/freshness.dart';
import '../widgets/glyph.dart';
import '../widgets/status_row.dart';

class FacilityHoursCard extends StatelessWidget {
  const FacilityHoursCard({
    super.key,
    required this.result,
    this.facilityName,
    this.compact = false,
    this.dragHandle,
  });

  final Result<Collection<RecreationFacility>> result;
  final String? facilityName;
  final bool compact;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <RecreationFacility>[];
    final facilities = facilityName == null
        ? all
        : [for (final facility in all) if (facility.name == facilityName) facility];
    return CardShell(
      title: facilityName ?? 'Facility hours',
      glyph: GlyphKind.buildings,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      child: switch ((result.isPriming, facilities.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading facility hours'),
        (_, true) => const EmptyState(
          kind: EmptyKind.sourceDown,
          title: 'Facility hours are unavailable',
        ),
        _ => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final facility in facilities.take(compact ? 1 : 5))
              _FacilityRow(facility: facility),
          ],
        ),
      },
    );
  }
}

class _FacilityRow extends StatelessWidget {
  const _FacilityRow({required this.facility});

  final RecreationFacility facility;

  static String _time(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return value;
    final hour = int.tryParse(parts.first);
    if (hour == null) return value;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final shown = hour % 12 == 0 ? 12 : hour % 12;
    return '$shown:${parts[1]} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final day = facility.days.isEmpty ? null : facility.days.first;
    final open = day != null && !day.closed && day.spans.isNotEmpty;
    final hours = day == null
        ? 'No hours published'
        : !open
        ? (day.note ?? 'Closed today')
        : day.spans
              .map((span) => '${_time(span.opensAt)} to ${_time(span.closesAt)}')
              .join(',  ');
    final semantic = Semantic.of(context);
    return StatusRow(
      icon: facility.name.toLowerCase().contains('pool')
          ? Icons.pool_rounded
          : Icons.fitness_center_rounded,
      title: facility.name,
      subtitle: hours,
      accent: open ? semantic.open : semantic.closed,
      emphasis: open ? RowEmphasis.normal : RowEmphasis.dimmed,
    );
  }
}

class DashboardMapCard extends StatelessWidget {
  const DashboardMapCard({
    super.key,
    required this.result,
    required this.events,
    this.dragHandle,
  });

  final Result<Collection<CampusMapFeature>> result;
  final Result<Collection<CampusEvent>> events;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) => CardShell(
    title: 'Campus map',
    glyph: GlyphKind.buildings,
    state: result.state,
    fetchedAt: result.fetchedAt,
    dragHandle: dragHandle,
    child: CampusMapView(result: result, events: events),
  );
}
