library;

import 'package:flutter/material.dart';

import '../data/campus_time.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/todays_hours.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/campus_map.dart';
import '../widgets/card_shell.dart';
import '../widgets/compact_card.dart';
import '../widgets/context_actions.dart';
import '../widgets/empty_state.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';

// hand kept, rec names are long
const Map<String, String> _facilityShortNames = {
  'Judson/Hale Aquatics Center': 'Pool',
  'Wiedman Fitness Center': 'Gym',
  'Red Barn Climbing': 'Climbing',
  'Gordon Field House': 'Field House',
  'Field House Indoor Track': 'Track',
  'Hale-Andrews Student Life Center (SLC)': 'SLC',
  'Outdoor Tennis Courts': 'Tennis',
  'Turf Field': 'Turf',
};

/// A label short enough for a half width card. Unknown names fall back to
/// their first word.
String facilityShortName(String name) {
  final known = _facilityShortNames[name];
  if (known != null) return known;
  final first = name.trim().split(RegExp(r'[\s/]+')).first;
  return first.isEmpty ? name : first;
}

/// The pool when there is one, which is what a new facility card starts as.
String? defaultFacilityName(List<RecreationFacility> facilities) {
  for (final facility in facilities) {
    if (facility.name.toLowerCase().contains('aquatics')) return facility.name;
  }
  return facilities.isEmpty ? null : facilities.first.name;
}

List<({String opens, String closes})> _spansOn(RecreationFacility facility, DateTime date) {
  final day = facility.dayOn(date);
  if (day == null || day.closed) return const [];
  return [for (final span in day.spans) (opens: span.opensAt, closes: span.closesAt)];
}

/// The compact answer at the campus wall clock [now]: what happens next today,
/// and tomorrow's first opening once today is done. Null value when no hours
/// are published for today.
({String? value, String? caption, bool quiet}) facilityCompact(RecreationFacility facility, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (facility.dayOn(today) == null) return (value: null, caption: null, quiet: true);
  final change = nextChange(_spansOn(facility, today), now.hour * 60 + now.minute);
  switch (change.kind) {
    case ChangeKind.opens:
      return (value: 'Opens ${clockLabel(change.minute!)}', caption: null, quiet: true);
    case ChangeKind.closes:
      return (value: 'Until ${clockLabel(change.minute!)}', caption: null, quiet: false);
    case ChangeKind.closedToday:
      final tomorrow = nextChange(_spansOn(facility, DateTime(now.year, now.month, now.day + 1)), 0);
      final caption = tomorrow.kind == ChangeKind.closedToday ? null : 'Opens ${tomorrow.kind == ChangeKind.closes ? 'midnight' : clockLabel(tomorrow.minute!)} tomorrow';
      return (value: 'Closed today', caption: caption, quiet: true);
  }
}

class FacilityHoursCard extends StatelessWidget {
  const FacilityHoursCard({
    super.key,
    required this.result,
    this.facilityName,
    this.compact = false,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<RecreationFacility>> result;
  final String? facilityName;
  final bool compact;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final all = result.value?.data ?? const <RecreationFacility>[];
    if (compact && Insets.phone(context)) return _compact(context, all);
    final facilities = facilityName == null
        ? all
        : [
            for (final facility in all)
              if (facility.name == facilityName) facility,
          ];
    return CardShell(
      title: facilityName ?? 'Facility hours',
      glyph: AppIconKind.buildings,
      state: result.state,
      fetchedAt: result.fetchedAt,
      dragHandle: dragHandle,
      onOpen: onShowAll,
      openLabel: 'opens Campus',
      child: switch ((result.isPriming, facilities.isEmpty)) {
        (true, _) => const PrimingPlaceholder(label: 'Loading facility hours'),
        (_, true) => const EmptyState(
          kind: EmptyKind.sourceDown,
          title: 'Hours unavailable',
        ),
        // Kept as a plain Column rather than BoundedList, deliberately.
        // BoundedList pins every row to StatusRow.height so its arithmetic is
        // exact, but a facility's hours subtitle wraps to two lines at narrow
        // widths and overflows that box by 4px. The fixed-height contract is
        // the thing that does not hold here.
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

extension on FacilityHoursCard {
  // compact needs one facility, the pool if none was picked
  Widget _compact(BuildContext context, List<RecreationFacility> all) {
    final name = facilityName ?? defaultFacilityName(all);
    final facility = all.where((f) => f.name == name).firstOrNull;
    final answer = facility == null || result.isPriming
        ? (value: null, caption: null, quiet: true)
        : facilityCompact(facility, CampusTime.wallNow());
    return CompactCard(
      label: name == null ? 'Facility' : facilityShortName(name),
      value: answer.value,
      caption: answer.caption,
      quiet: answer.quiet,
      dragHandle: dragHandle,
      onOpen: onShowAll,
      openLabel: 'opens Campus',
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
    final day = facility.dayOn(CampusTime.wallDate());
    final open = day != null && !day.closed && day.spans.isNotEmpty;
    final hours = day == null
        ? (facility.droppedNested > 0
              ? 'Hours unavailable'
              : 'No hours published')
        : !open
        ? (day.note ?? 'Closed today')
        : day.spans
              .map(
                (span) => '${_time(span.opensAt)} to ${_time(span.closesAt)}',
              )
              .join(',  ');
    final semantic = Semantic.of(context);
    return StatusRow(
      icon: facility.name.toLowerCase().contains('pool')
          ? AppIconKind.swimming
          : AppIconKind.gym,
      title: facility.name,
      subtitle: hours,
      accent: open ? semantic.open : semantic.closed,
      emphasis: open ? RowEmphasis.normal : RowEmphasis.dimmed,
      actions: [MenuAction.copy('${facility.name}\n$hours')],
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
    glyph: AppIconKind.buildings,
    state: result.state,
    fetchedAt: result.fetchedAt,
    dragHandle: dragHandle,
    child: CampusMapView(result: result, events: events),
  );
}
