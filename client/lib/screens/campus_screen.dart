/// Campus tab.
///
/// The things that are neither dining nor events: where to collect mail, when
/// the post offices are open, and what is free right now in the SHED.
///
/// Note on the SHED: its hours are hardcoded in the server's static config
/// because the make.rit.edu hours feed is broken (it reports closed on every
/// row). Equipment availability from that same API is trusted and live.
library;

import 'package:flutter/material.dart';

import '../cards/housing_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';
import '../widgets/content_column.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';

class CampusScreen extends StatefulWidget {
  const CampusScreen({super.key, required this.api, required this.areas});

  final ApiClient api;
  final Result<Collection<HousingArea>> areas;

  @override
  State<CampusScreen> createState() => _CampusScreenState();
}

class _CampusScreenState extends State<CampusScreen> {
  Result<Collection<PostOffice>> _offices =
      const Result(value: null, state: DataState.priming);
  Result<List<MakerSpaceHours>> _shed =
      const Result(value: null, state: DataState.priming);
  Result<Collection<RoomSummary>> _rooms =
      const Result(value: null, state: DataState.priming);
  Result<Collection<RecreationFacility>> _rec =
      const Result(value: null, state: DataState.priming);

  @override
  void initState() {
    super.initState();
    widget.api.postOffices().listen((r) {
      if (mounted) setState(() => _offices = r);
    });
    widget.api.makerspaceHours().listen((r) {
      if (mounted) setState(() => _shed = r);
    });
    widget.api.makerspaceRooms().listen((r) {
      if (mounted) setState(() => _rooms = r);
    });
    widget.api.recreation().listen((r) {
      if (mounted) setState(() => _rec = r);
    });
  }

  @override
  Widget build(BuildContext context) {

    return ContentColumn(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          HousingCard(areas: widget.areas, api: widget.api),
          const SizedBox(height: 22),

          _Heading(
            title: 'Post offices',
            subtitle: 'Mail is collected at the counter after an email notice. '
                'There are no mailboxes.',
            state: _offices.state,
            fetchedAt: _offices.fetchedAt,
          ),
          for (final office in _offices.value?.data ?? const <PostOffice>[])
            _PostOfficeBlock(office: office),
          if (_offices.isPriming) const PrimingPlaceholder(label: 'Loading post offices'),

          const SizedBox(height: 22),

          _Heading(
            title: 'Gym and pool',
            subtitle: 'Today first. A facility can run several sessions in a '
                'day, so each one is listed separately.',
            state: _rec.state,
            fetchedAt: _rec.fetchedAt,
          ),
          if (_rec.isPriming)
            const PrimingPlaceholder(label: 'Loading facility hours')
          else
            for (final facility
                in _rec.value?.data ?? const <RecreationFacility>[])
              _RecreationRow(facility: facility),

          const SizedBox(height: 22),

          _Heading(
            title: 'SHED makerspace',
            subtitle: 'Equipment availability is live. Hours are hand '
                'maintained, because the upstream hours feed is broken.',
            state: _rooms.state,
            fetchedAt: _rooms.fetchedAt,
          ),
          for (final space in _shed.value ?? const <MakerSpaceHours>[])
            _ShedHoursBlock(space: space),
          _EquipmentBlock(result: _rooms),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.subtitle,
    required this.state,
    this.fetchedAt,
  });

  final String title;
  final String subtitle;
  final DataState state;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          const SizedBox(height: 3),
          Text(subtitle, style: text.bodySmall),
          FreshnessLine(state: state, fetchedAt: fetchedAt),
        ],
      ),
    );
  }
}

/// Weekday order for display, and a compact "Mon to Fri" style label.
const _weekOrder = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

String _dayLabel(List<String> days) {
  if (days.isEmpty) return '';
  final indices = days.map(_weekOrder.indexOf).toList()..sort();
  final short = [for (final i in indices) _weekOrder[i].substring(0, 3).toLowerCase()];
  final capitalised = [
    for (final s in short) '${s[0].toUpperCase()}${s.substring(1)}'
  ];
  // Contiguous runs collapse to a range.
  final contiguous = indices.length > 1 &&
      indices.last - indices.first == indices.length - 1;
  if (contiguous) return '${capitalised.first} to ${capitalised.last}';
  return capitalised.join(', ');
}

String _time(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts[1];
  if (hour == 0 && minute == '00') return 'midnight';
  if (hour == 12 && minute == '00') return 'noon';
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final display = hour % 12 == 0 ? 12 : hour % 12;
  return '$display:$minute $suffix';
}

String _serviceLabel(String service) => switch (service) {
      'package_pickup' => 'Package pickup',
      'shipping_window' => 'Shipping window',
      _ => 'Hours',
    };

/// Which season's hours are in force.
///
/// RIT publishes fall and summer separately. Showing both at once is noise:
/// nobody standing outside the post office in September cares what July looked
/// like. Fall term runs roughly late August to mid May.
String currentSeason(DateTime now) {
  final month = now.month;
  final isSummer = month == 6 || month == 7 || (month == 8 && now.day < 22);
  return isSummer ? 'summer' : 'fall';
}

class _PostOfficeBlock extends StatelessWidget {
  const _PostOfficeBlock({required this.office});

  final PostOffice office;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final season = currentSeason(DateTime.now());

    // Only what is in force. Fall back to everything if a season is missing,
    // so a config gap shows something rather than an empty card.
    var rules = office.hours.where((r) => r.season == season).toList();
    if (rules.isEmpty) rules = office.hours;

    final services = <String, List<HoursRule>>{};
    for (final rule in rules) {
      services.putIfAbsent(rule.service, () => []).add(rule);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Shapes.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: StatusRow.badgeSize,
                  height: StatusRow.badgeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.32),
                  ),
                  child: Icon(Icons.local_post_office_rounded,
                      size: 21, color: scheme.primary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(office.name, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text('${office.street}  ${office.side} side',
                          style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final service in services.entries) ...[
              _ServiceHours(service: service.key, rules: service.value),
              const SizedBox(height: 12),
            ],
            if (office.locationNote != null) ...[
              Text(office.locationNote!, style: text.bodySmall),
              const SizedBox(height: 12),
            ],
            if (office.email != null || office.phone != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (office.phone != null)
                    _ContactChip(icon: Icons.call_rounded, label: office.phone!),
                  if (office.email != null)
                    _ContactChip(icon: Icons.mail_rounded, label: office.email!),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One service, with its times set large and centred.
///
/// The times are the thing people came for, so they get the space rather than
/// being one column of a cramped table.
class _ServiceHours extends StatelessWidget {
  const _ServiceHours({required this.service, required this.rules});

  final String service;
  final List<HoursRule> rules;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Shapes.inner,
      ),
      child: Column(
        children: [
          Text(_serviceLabel(service).toUpperCase(), style: text.labelSmall),
          const SizedBox(height: 10),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  Text(
                    '${_time(rule.opensAt)} to ${_time(rule.closesAt)}',
                    textAlign: TextAlign.center,
                    style: text.displayMedium?.copyWith(
                      fontSize: 27,
                      fontVariations: Weights.medium,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dayLabel(rule.days),
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: Shapes.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 7),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// One facility, today's sessions inline, the rest of the week on tap.
class _RecreationRow extends StatelessWidget {
  const _RecreationRow({required this.facility});

  final RecreationFacility facility;

  static IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.contains('aquatic') || n.contains('pool')) return Icons.pool_rounded;
    if (n.contains('climb')) return Icons.terrain_rounded;
    if (n.contains('tennis')) return Icons.sports_tennis_rounded;
    if (n.contains('turf') || n.contains('field')) return Icons.sports_soccer_rounded;
    if (n.contains('track')) return Icons.directions_run_rounded;
    if (n.contains('office')) return Icons.badge_rounded;
    return Icons.fitness_center_rounded;
  }

  String _spansOf(RecreationDay day) => day.closed || day.spans.isEmpty
      ? (day.note ?? 'Closed')
      : day.spans
          .map((s) => '${_time(s.opensAt)} to ${_time(s.closesAt)}')
          .join(',  ');

  @override
  Widget build(BuildContext context) {
    final semantic = Semantic.of(context);
    final today = facility.days.isEmpty ? null : facility.days.first;
    final open = today != null && !today.closed && today.spans.isNotEmpty;

    return StatusRow(
      icon: _icon(facility.name),
      title: facility.name,
      subtitle: today == null ? 'No hours published' : _spansOf(today),
      accent: open ? semantic.open : semantic.closed,
      emphasis: open ? RowEmphasis.normal : RowEmphasis.dimmed,
      onTap: facility.days.length < 2
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => _WeekSheet(facility: facility),
              ),
      trailing: facility.days.length < 2
          ? null
          : Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
    );
  }
}

/// The whole published week for one facility.
class _WeekSheet extends StatelessWidget {
  const _WeekSheet({required this.facility});

  final RecreationFacility facility;

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final semantic = Semantic.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(facility.name, style: text.titleLarge?.copyWith(fontSize: 22)),
            const SizedBox(height: 14),
            for (var i = 0; i < facility.days.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        i == 0
                            ? 'Today'
                            : _dayNames[facility.days[i].serviceDate.weekday - 1],
                        style: text.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: facility.days[i].closed ||
                              facility.days[i].spans.isEmpty
                          ? Text(
                              facility.days[i].note ?? 'Closed',
                              style: text.bodyMedium
                                  ?.copyWith(color: semantic.closed),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final span in facility.days[i].spans)
                                  Text(
                                    '${_time(span.opensAt)} to ${_time(span.closesAt)}',
                                    style: text.bodyMedium,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'From RIT Recreation and Wellness.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShedHoursBlock extends StatelessWidget {
  const _ShedHoursBlock({required this.space});

  final MakerSpaceHours space;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final rules = [...space.hours]..sort((a, b) =>
        _weekOrder.indexOf(a.days.isEmpty ? '' : a.days.first)
            .compareTo(_weekOrder.indexOf(b.days.isEmpty ? '' : b.days.first)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Shapes.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: StatusRow.badgeSize,
                  height: StatusRow.badgeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.32),
                  ),
                  child: Icon(Icons.construction_rounded,
                      size: 21, color: scheme.primary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(space.name, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(space.location, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final rule in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(_dayLabel(rule.days), style: text.bodySmall),
                    ),
                    Expanded(
                      child: Text(
                        '${_time(rule.opensAt)} to ${_time(rule.closesAt)}',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Provisional. Cross check against rit.edu/shed.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentBlock extends StatelessWidget {
  const _EquipmentBlock({required this.result});

  final Result<Collection<RoomSummary>> result;

  @override
  Widget build(BuildContext context) {
    if (result.isPriming) {
      return const PrimingPlaceholder(label: 'Loading equipment');
    }

    final rooms = [...(result.value?.data ?? const <RoomSummary>[])]
      ..sort((a, b) => b.available.compareTo(a.available));
    if (rooms.isEmpty) {
      return const EmptyNote(text: 'No equipment cached yet.');
    }

    final semantic = Semantic.of(context);
    final totalFree = rooms.fold<int>(0, (n, r) => n + r.available);
    final totalBusy = rooms.fold<int>(0, (n, r) => n + r.inUse);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupHeader(
          icon: Icons.precision_manufacturing_rounded,
          title: '$totalFree free now, $totalBusy in use',
          count: rooms.fold<int>(0, (n, r) => n + r.machines),
        ),
        for (final room in rooms)
          StatusRow(
            icon: _iconForRoom(room.room),
            title: room.room,
            subtitle: '${room.machines} machine${room.machines == 1 ? '' : 's'}',
            accent: room.available > 0 ? semantic.open : semantic.closed,
            emphasis:
                room.available > 0 ? RowEmphasis.normal : RowEmphasis.dimmed,
            trailing: Text(
              room.available > 0 ? '${room.available} free' : 'none free',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: room.available > 0 ? semantic.open : semantic.closed,
                  ),
            ),
          ),
      ],
    );
  }

  static IconData _iconForRoom(String room) {
    final r = room.toLowerCase();
    if (r.contains('3d print')) return Icons.view_in_ar_rounded;
    if (r.contains('laser')) return Icons.blur_on_rounded;
    if (r.contains('wood')) return Icons.carpenter_rounded;
    if (r.contains('metal')) return Icons.hardware_rounded;
    if (r.contains('textile')) return Icons.checkroom_rounded;
    if (r.contains('electronic')) return Icons.memory_rounded;
    if (r.contains('vinyl')) return Icons.content_cut_rounded;
    return Icons.build_rounded;
  }
}
