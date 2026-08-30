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

import '../widgets/empty_state.dart';
import '../cards/housing_card.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';
import '../widgets/places_sheet.dart';
import '../widgets/glyph.dart';
import '../widgets/section_nav.dart';
import '../widgets/week_grid.dart';

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
  Result<Collection<PlaceKind>> _kinds =
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
    widget.api.placeKinds().listen((r) {
      if (mounted) setState(() => _kinds = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Five unrelated things used to stack in one scroll, so anything below the
    // first two disappeared. Same nav idiom as Settings.
    return SectionScaffold(
      sections: [
        SectionSpec(
          id: 'mail',
          title: 'Mail',
          subtitle: 'Your address, and both post offices',
          icon: Icons.local_post_office_rounded,
          glyph: GlyphKind.housing,
          builder: (context) => _MailSection(
            api: widget.api,
            areas: widget.areas,
            offices: _offices,
          ),
        ),
        SectionSpec(
          id: 'find',
          title: 'Find on campus',
          subtitle: 'Fountains, restrooms, blue lights, bus stops',
          icon: Icons.travel_explore_rounded,
          glyph: GlyphKind.buildings,
          builder: (context) => _FindSection(api: widget.api, kinds: _kinds),
        ),
        SectionSpec(
          id: 'rec',
          title: 'Gym and pool',
          subtitle: 'Facility hours for the week',
          icon: Icons.fitness_center_rounded,
          builder: (context) => _RecreationSection(result: _rec),
        ),
        SectionSpec(
          id: 'shed',
          title: 'SHED makerspace',
          glyph: GlyphKind.makerspace,
          subtitle: 'Live equipment availability',
          icon: Icons.construction_rounded,
          builder: (context) => _ShedSection(shed: _shed, rooms: _rooms),
        ),
      ],
    );
  }
}

class _MailSection extends StatelessWidget {
  const _MailSection({
    required this.api,
    required this.areas,
    required this.offices,
  });

  final ApiClient api;
  final Result<Collection<HousingArea>> areas;
  final Result<Collection<PostOffice>> offices;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
        children: [
          HousingCard(areas: areas, api: api),
          const SizedBox(height: 22),
          _Heading(
            glyph: GlyphKind.postOffice,
            title: 'Post offices',
            subtitle: 'Mail is collected at the counter after an email notice. '
                'There are no mailboxes.',
            state: offices.state,
            fetchedAt: offices.fetchedAt,
          ),
          if (offices.isPriming)
            const PrimingPlaceholder(label: 'Loading post offices')
          else
            for (final office in offices.value?.data ?? const <PostOffice>[])
              _PostOfficeBlock(office: office),
        ],
      );
}

class _FindSection extends StatelessWidget {
  const _FindSection({required this.api, required this.kinds});

  final ApiClient api;
  final Result<Collection<PlaceKind>> kinds;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
        children: [
          _Heading(
            title: 'Find on campus',
            subtitle: 'From the campus map, with the building, floor and a note '
                'on where exactly to look.',
            state: kinds.state,
            fetchedAt: kinds.fetchedAt,
          ),
          if (kinds.isPriming)
            const PrimingPlaceholder(label: 'Loading places')
          else
            for (final kind in kinds.value?.data ?? const <PlaceKind>[])
              StatusRow(
                icon: iconForPlaceKind(kind.kind),
                title: kind.kindName,
                subtitle: '${kind.count} on campus',
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  constraints: const BoxConstraints(maxWidth: 720),
                  builder: (context) => PlacesSheet(
                    api: api,
                    kind: kind.kind,
                    title: kind.kindName,
                    icon: iconForPlaceKind(kind.kind),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
        ],
      );
}

class _RecreationSection extends StatelessWidget {
  const _RecreationSection({required this.result});

  final Result<Collection<RecreationFacility>> result;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
        children: [
          _Heading(
            title: 'Gym and pool',
            subtitle: 'Today first. A facility can run several sessions in a '
                'day, so each one is listed separately.',
            state: result.state,
            fetchedAt: result.fetchedAt,
          ),
          if (result.isPriming)
            const PrimingPlaceholder(label: 'Loading facility hours')
          else
            for (final facility
                in result.value?.data ?? const <RecreationFacility>[])
              _RecreationRow(facility: facility),
        ],
      );
}

class _ShedSection extends StatelessWidget {
  const _ShedSection({required this.shed, required this.rooms});

  final Result<List<MakerSpaceHours>> shed;
  final Result<Collection<RoomSummary>> rooms;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
        children: [
          _Heading(
            glyph: GlyphKind.makerspace,
            title: 'SHED makerspace',
            subtitle: 'Equipment availability is live. Hours are hand '
                'maintained, because the upstream hours feed is broken.',
            state: rooms.state,
            fetchedAt: rooms.fetchedAt,
          ),
          for (final space in shed.value ?? const <MakerSpaceHours>[])
            _ShedHoursBlock(space: space),
          _EquipmentBlock(result: rooms),
        ],
      );
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.subtitle,
    required this.state,
    this.fetchedAt,
    this.glyph,
  });

  final String title;
  final String subtitle;
  final DataState state;
  final DateTime? fetchedAt;

  /// Section identity, which is what the custom glyphs are for. Sections the
  /// spec does not cover simply leave this null and show no glyph.
  final GlyphKind? glyph;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (glyph != null) ...[
                Glyph(glyph!, size: 22),
                const SizedBox(width: 9),
              ],
              Flexible(child: Text(title, style: text.titleLarge)),
            ],
          ),
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
            const SizedBox(height: 18),
            for (final service in services.entries) ...[
              _ServiceHours(service: service.key, rules: service.value),
              const SizedBox(height: 14),
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

/// Rules sharing a day label, collapsed into one entry.
///
/// The shipping window runs 9:00 to 1:00 and 1:30 to 4:00 on the same weekdays,
/// which arrives as two rules and rendered as two blocks each captioned
/// "MON TO FRI". Two identical headings read as two separate rules rather than
/// as one closure over lunch.
List<(String, List<HoursRule>)> groupRulesByDay(List<HoursRule> rules) {
  final out = <(String, List<HoursRule>)>[];
  for (final rule in rules) {
    final label = _dayLabel(rule.days);
    if (out.isNotEmpty && out.last.$1 == label) {
      out.last.$2.add(rule);
    } else {
      out.add((label, [rule]));
    }
  }
  return out;
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
    final grouped = groupRulesByDay(rules);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Shapes.inner,
      ),
      child: Column(
        children: [
          Text(_serviceLabel(service).toUpperCase(), style: text.labelSmall),
          const SizedBox(height: 16),
          for (var i = 0; i < grouped.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 16),
              // A rule per line ran together. A hairline separates them so
              // "weekdays" and "Saturday" read as two facts, not one block.
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
            ],
            Column(
              children: [
                // The day comes first and small, so the eye lands on the time.
                Text(
                  grouped[i].$1.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: text.labelSmall,
                ),
                const SizedBox(height: 6),
                // A split shift is several spans on the same days. They share
                // one heading, because repeating "MON TO FRI" above each half
                // reads as two different rules rather than one lunch break.
                for (var j = 0; j < grouped[i].$2.length; j++) ...[
                  if (j > 0) const SizedBox(height: 4),
                  Text(
                    '${_time(grouped[i].$2[j].opensAt)} to '
                    '${_time(grouped[i].$2[j].closesAt)}',
                    textAlign: TextAlign.center,
                    style: text.displayMedium?.copyWith(
                      fontSize: 29,
                      height: 1.15,
                      fontVariations: Weights.medium,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ],
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
/// The whole published week for one facility, as a grid.
class _WeekSheet extends StatelessWidget {
  const _WeekSheet({required this.facility});

  final RecreationFacility facility;

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final rows = [
      for (var i = 0; i < facility.days.length; i++)
        WeekRow(
          label: i == 0
              ? 'Today'
              : _dayNames[facility.days[i].serviceDate.weekday - 1],
          note: facility.days[i].note,
          spans: [
            for (final span in facility.days[i].spans)
              DaySpan(
                startMinutes: _minutes(span.opensAt),
                endMinutes: _minutes(span.closesAt),
                label: '${_time(span.opensAt)} to ${_time(span.closesAt)}',
              ),
          ],
        ),
    ];

    // Fit the window to the data rather than assuming a range.
    final starts = rows.expand((r) => r.spans).map((s) => s.startMinutes);
    final ends = rows.expand((r) => r.spans).map((s) => s.endMinutes);
    final from = starts.isEmpty ? 6 : (starts.reduce((a, b) => a < b ? a : b) ~/ 60);
    final to = ends.isEmpty ? 24 : ((ends.reduce((a, b) => a > b ? a : b) + 59) ~/ 60);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(facility.name, style: text.titleLarge?.copyWith(fontSize: 22)),
            const SizedBox(height: 16),
            WeekGrid(
              rows: rows,
              highlightIndex: 0,
              startHour: from.clamp(0, 23),
              endHour: to.clamp(1, 24),
            ),
            const SizedBox(height: 14),
            Text('From RIT Recreation and Wellness.', style: text.bodySmall),
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
      return const EmptyState(
        kind: EmptyKind.sourceDown,
        title: 'Equipment availability is unavailable',
        compact: false,
      );
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
