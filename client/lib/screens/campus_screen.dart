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
import 'package:intl/intl.dart';

import '../widgets/empty_state.dart';
import '../cards/housing_card.dart';
import '../models/api_models.dart';
import '../data/campus_time.dart';
import '../services/todays_hours.dart';
import '../services/api.dart';
import '../services/open_link.dart';
import '../services/preferences.dart';
import '../services/academic_dates.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';
import '../widgets/freshness.dart';
import '../widgets/status_row.dart';
import '../widgets/places_sheet.dart';
import '../widgets/glyph.dart';
import '../widgets/section_nav.dart';
import '../widgets/week_grid.dart';
import '../services/subscriptions.dart';

class CampusScreen extends StatefulWidget {
  const CampusScreen({
    super.key,
    required this.api,
    required this.areas,
    this.events = const Result(value: null, state: DataState.priming),
    this.now,
  });

  final ApiClient api;
  final Result<Collection<HousingArea>> areas;
  final Result<Collection<CampusEvent>> events;
  final DateTime? now;

  @override
  State<CampusScreen> createState() => _CampusScreenState();
}

class _CampusScreenState extends State<CampusScreen> {
  Result<Collection<PostOffice>> _offices = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<List<MakerSpaceHours>> _shed = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<RoomSummary>> _rooms = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<RecreationFacility>> _rec = const Result(
    value: null,
    state: DataState.priming,
  );
  Result<Collection<PlaceKind>> _kinds = const Result(
    value: null,
    state: DataState.priming,
  );

  /// Held so they can be cancelled. Dangling subscriptions let a previous
  /// visit's results land after the current ones and overwrite them.
  final _subscriptions = Subscriptions();

  @override
  void initState() {
    super.initState();
    Preferences.instance.addListener(_onPreferencesChanged);
    _subscriptions.add(
      widget.api.postOffices().listen((r) {
        if (mounted) setState(() => _offices = r);
      }),
    );
    _subscriptions.add(
      widget.api.makerspaceHours().listen((r) {
        if (mounted) setState(() => _shed = r);
      }),
    );
    _subscriptions.add(
      widget.api.makerspaceRooms().listen((r) {
        if (mounted) setState(() => _rooms = r);
      }),
    );
    _subscriptions.add(
      widget.api.recreation().listen((r) {
        if (mounted) setState(() => _rec = r);
      }),
    );
    _subscriptions.add(
      widget.api.placeKinds().listen((r) {
        if (mounted) setState(() => _kinds = r);
      }),
    );
  }

  @override
  void dispose() {
    Preferences.instance.removeListener(_onPreferencesChanged);
    _subscriptions.dispose();
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (mounted) setState(() {});
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
          id: 'dates',
          title: 'Academic dates',
          subtitle: 'Deadlines, breaks, reading days and finals',
          icon: Icons.event_available_rounded,
          builder: (context) => _AcademicDatesSection(now: widget.now),
        ),
        SectionSpec(
          id: 'shuttles',
          title: 'Shuttles',
          subtitle: 'Today’s routes for where you live',
          icon: Icons.directions_bus_rounded,
          builder: (context) => _ShuttleSection(
            areas: widget.areas.value?.data ?? const <HousingArea>[],
            now: widget.now,
          ),
        ),
        SectionSpec(
          id: 'safety',
          title: 'Safety',
          subtitle: 'Emergency, text and non-emergency contacts',
          icon: Icons.health_and_safety_rounded,
          builder: (context) => const _SafetySection(),
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

typedef _ShuttleRoute = ({
  int number,
  String name,
  String hours,
  bool weekday,
  bool weekend,
});

const _campusConnection3 = (
  number: 3,
  name: 'Campus Connection Shuttle',
  hours: '7:00 AM–11:16 PM',
  weekday: true,
  weekend: false,
);
const _campusConnection4 = (
  number: 4,
  name: 'Campus Connection Shuttle',
  hours: '5:00 AM–6:00 PM',
  weekday: true,
  weekend: false,
);
const _campusConnection5 = (
  number: 5,
  name: 'Campus Connection Shuttle',
  hours: '11:20 AM–4:30 PM',
  weekday: true,
  weekend: false,
);
const _eastMorning = (
  number: 9,
  name: 'Early Morning East Residence',
  hours: '7:00 AM–6:51 PM',
  weekday: true,
  weekend: false,
);
const _eastEvening = (
  number: 11,
  name: 'East Residence Shuttle',
  hours: '7:00 PM–11:56 PM',
  weekday: true,
  weekend: false,
);
const _retail = (
  number: 12,
  name: 'Retail Shuttle',
  hours: '7:00 AM–11:50 PM',
  weekday: false,
  weekend: true,
);
const _campusInn = (
  number: 13,
  name: 'Campus & Inn Shuttle',
  hours: '7:47 AM–12:33 AM',
  weekday: false,
  weekend: true,
);
const _perkins = (
  number: 7,
  name: 'Perkins Green',
  hours: '7:00 AM–6:47 PM',
  weekday: true,
  weekend: false,
);

const Map<String, List<_ShuttleRoute>> _shuttlesByHome = {
  'global-village': [
    _campusConnection3,
    _campusConnection4,
    _campusConnection5,
    _retail,
    _campusInn,
  ],
  'residence-halls': [
    _campusConnection3,
    _campusConnection4,
    _campusConnection5,
    _eastMorning,
    _eastEvening,
    _retail,
    _campusInn,
  ],
  'perkins-green': [_perkins, _eastMorning, _eastEvening, _campusInn],
  'riverknoll': [
    _campusConnection3,
    _campusConnection4,
    _campusConnection5,
    _campusInn,
  ],
  'university-commons': [
    _campusConnection3,
    _campusConnection4,
    _campusConnection5,
    _campusInn,
  ],
};

class _ShuttleSection extends StatelessWidget {
  const _ShuttleSection({required this.areas, this.now});

  final List<HousingArea> areas;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final homeId = Preferences.instance.homeArea;
    final home = areas.where((area) => area.id == homeId).firstOrNull;
    final clock = now ?? CampusTime.wallNow();
    final weekend =
        clock.weekday == DateTime.saturday || clock.weekday == DateTime.sunday;
    final laborDay = clock.year == 2026 && clock.month == 9 && clock.day == 7;
    final routes = laborDay
        ? const <_ShuttleRoute>[
            (
              number: 1,
              name: 'RIT RTS Connection — Holiday',
              hours: 'See the holiday timetable',
              weekday: true,
              weekend: true,
            ),
            (
              number: 14,
              name: 'Campus & Inn Break Shuttle',
              hours: '7:20 AM–12:06 AM',
              weekday: true,
              weekend: true,
            ),
          ]
        : (_shuttlesByHome[homeId] ?? const <_ShuttleRoute>[])
              .where((route) => weekend ? route.weekend : route.weekday)
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      children: [
        _Heading(
          title: laborDay
              ? 'Labor Day service'
              : 'Today from ${home?.name ?? 'home'}',
          subtitle: laborDay
              ? 'Reduced service published for Monday, September 7.'
              : 'Scheduled windows, not live arrivals. Arrive at the stop at least five minutes early.',
          state: DataState.ok,
        ),
        if (homeId == null)
          const EmptyState(
            kind: EmptyKind.notFound,
            title: 'Choose your housing area in Mail first',
            compact: false,
          )
        else if (!laborDay && !_shuttlesByHome.containsKey(homeId))
          const EmptyState(
            kind: EmptyKind.notFound,
            title: 'RIT does not publish a route table for this housing area',
            compact: false,
          )
        else if (routes.isEmpty)
          const EmptyState(
            kind: EmptyKind.noEvents,
            title: 'No scheduled routes today',
            compact: false,
          )
        else
          for (final route in routes)
            StatusRow(
              icon: Icons.directions_bus_rounded,
              title: '${route.number} · ${route.name}',
              subtitle: route.hours,
            ),
        const SizedBox(height: 8),
        Text(
          'Live vehicle locations and arrival estimates are available in TripShot.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AcademicDatesSection extends StatelessWidget {
  const _AcademicDatesSection({this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final upcoming = upcomingAcademicMilestones(now: now, limit: 8);
    final formatter = DateFormat('EEE, MMM d');

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      children: [
        const _Heading(
          title: 'What is next',
          subtitle: 'Official Rochester campus dates for 2026–27. Past dates disappear automatically.',
          state: DataState.ok,
        ),
        if (upcoming.isEmpty)
          const EmptyState(
            kind: EmptyKind.noEvents,
            title: 'No more dates in this academic year',
            compact: false,
          )
        else
          for (var index = 0; index < upcoming.length; index++)
            StatusRow(
              icon: index == 0
                  ? Icons.upcoming_rounded
                  : Icons.calendar_today_rounded,
              title: upcoming[index].title,
              subtitle: upcoming[index].detail,
              trailing: Text(
                formatter.format(upcoming[index].date),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
      ],
    );
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection();

  static const contacts = [
    (
      label: 'Emergency call',
      number: '585-475-3333',
      icon: Icons.emergency_rounded,
    ),
    (label: 'Emergency text', number: '585-205-8333', icon: Icons.sms_rounded),
    (
      label: 'General calls',
      number: '585-475-2853',
      icon: Icons.support_agent_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
    children: [
      const _Heading(
        title: 'RIT Public Safety',
        subtitle: 'Available 24 hours a day. For an immediate life-threatening emergency, call 911.',
        state: DataState.ok,
      ),
      for (final contact in contacts)
        StatusRow(
          icon: contact.icon,
          title: contact.label,
          subtitle: contact.number,
          trailing: const Icon(Icons.call_rounded, size: 18),
          semanticHint: 'Calls ${contact.number}',
          onTap: () => openOrCopy(
            context,
            phoneUri(contact.number),
            label: '${contact.label} number',
            copyText: contact.number,
          ),
        ),
      const SizedBox(height: 12),
      Text(
        'TigerSafe adds Mobile BlueLight, Friend Walk, safety alerts and assistance requests. This app does not replace TigerSafe.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
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
        subtitle:
            'Mail is collected at the counter after an email notice. '
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
        subtitle:
            'From the campus map, with the building, floor and a note '
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
        subtitle:
            'Today first. A facility can run several sessions in a '
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
        subtitle:
            'Equipment availability is live. Hours are hand '
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
  final short = [
    for (final i in indices) _weekOrder[i].substring(0, 3).toLowerCase(),
  ];
  final capitalised = [
    for (final s in short) '${s[0].toUpperCase()}${s.substring(1)}',
  ];
  // Contiguous runs collapse to a range.
  final contiguous =
      indices.length > 1 && indices.last - indices.first == indices.length - 1;
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

/// One line per service: what it is doing right now.
///
/// The full week stays underneath. This exists because reading a per service,
/// per weekday, per season table to work out whether to walk over is the wrong
/// amount of effort for the question.
class _TodayLine extends StatelessWidget {
  const _TodayLine({required this.today});

  final TodaysHours today;

  @override
  Widget build(BuildContext context) {
    if (today.state == ServiceState.unknown) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final semantic = Semantic.of(context);

    // Status is always stated in words. Colour never carries it alone.
    final (label, detail) = switch (today.state) {
      ServiceState.open => ('OPEN', 'until ${_clockAt(today.closesAt!)}'),
      // Between spans is not the same as finished, and saying "closed" alone
      // would send someone away minutes before it reopens.
      ServiceState.closedUntilLater => (
        'CLOSED',
        'opens ${_clockAt(today.opensAt!)}',
      ),
      ServiceState.closedForDay => (
        'CLOSED',
        today.spans.isEmpty ? 'not open today' : 'for the day',
      ),
      ServiceState.unknown => ('', ''),
    };

    final accent = today.isOpen ? semantic.open : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _serviceLabel(today.service),
              style: text.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
          Text(
            '$label \u00b7 $detail',
            style: text.bodySmall?.copyWith(
              color: today.isOpen ? accent : scheme.onSurfaceVariant,
              fontVariations: Weights.medium,
            ),
          ),
        ],
      ),
    );
  }
}

/// An instant as `4:30 PM`. Distinct from `_time`, which formats the config's
/// `"16:30"` strings; this one takes a resolved moment.
String _clockAt(DateTime instant) {
  final fields = CampusTime.fieldsOf(instant);
  final hour = fields.hour % 12 == 0 ? 12 : fields.hour % 12;
  final suffix = fields.hour < 12 ? 'AM' : 'PM';
  if (fields.minute == 0) return '$hour $suffix';
  return '$hour:${fields.minute.toString().padLeft(2, '0')} $suffix';
}

class _PostOfficeBlock extends StatelessWidget {
  const _PostOfficeBlock({required this.office});

  final PostOffice office;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Campus date, not the device's. A phone in another timezone must not
    // flip to summer hours a day early on the 21st.
    final season = currentSeason(CampusTime.fieldsOf(CampusTime.nowUtc()));

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
                  child: Icon(
                    Icons.local_post_office_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(office.name, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${office.street}  ${office.side} side',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // The answer to "can I go now", before the week's table. The table
            // is for planning; this is for standing outside deciding.
            for (final service in servicesIn(rules))
              _TodayLine(
                today: todaysHours(
                  service: service,
                  rules: rules,
                  now: CampusTime.nowUtc(),
                ),
              ),

            const SizedBox(height: 16),
            _ServiceModules(services: services, season: season),
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
                    _ContactChip(
                      icon: Icons.call_rounded,
                      label: office.phone!,
                    ),
                  if (office.email != null)
                    _ContactChip(
                      icon: Icons.mail_rounded,
                      label: office.email!,
                    ),
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

/// The service modules, side by side when there is room for them.
///
/// The spec asks for two across at 840px and above, and each module needs at
/// least 340px of content to keep its large centred times on one line. Below
/// that they stack, because a cramped module is worse than a tall column.
class _ServiceModules extends StatelessWidget {
  const _ServiceModules({required this.services, required this.season});

  final Map<String, List<HoursRule>> services;
  final String season;

  static const double _twoUpFrom = 840;
  static const double _minModuleWidth = 340;
  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    final entries = services.entries.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoUp =
            width >= _twoUpFrom &&
            (width - _gap) / 2 >= _minModuleWidth &&
            entries.length > 1;

        if (!twoUp) {
          return Column(
            children: [
              for (final entry in entries) ...[
                _ServiceHours(
                  service: entry.key,
                  rules: entry.value,
                  season: season,
                ),
                const SizedBox(height: _gap),
              ],
            ],
          );
        }

        // Reading order continues into the next row, so a third service does
        // not jump the queue to fill a hole.
        final rows = <Widget>[];
        for (var i = 0; i < entries.length; i += 2) {
          final left = entries[i];
          final right = i + 1 < entries.length ? entries[i + 1] : null;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ServiceHours(
                      service: left.key,
                      rules: left.value,
                      season: season,
                    ),
                  ),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: right == null
                        ? const SizedBox.shrink()
                        : _ServiceHours(
                            service: right.key,
                            rules: right.value,
                            season: season,
                          ),
                  ),
                ],
              ),
            ),
          );
          rows.add(const SizedBox(height: _gap));
        }
        return Column(children: rows);
      },
    );
  }
}

/// One service, as a self contained module.
///
/// Per `docs/post-office-hours-spec.md`. Package pickup and the shipping window
/// are never combined: they can run different seasons, days and hours, and
/// merging them would invent a schedule neither of them has.
///
/// The times are what people came for, so they stay large and centred. What the
/// module adds is a frame around them without turning them back into a table:
/// a quiet surface, a narrow route marker down the left, and the season stated
/// rather than assumed.
class _ServiceHours extends StatelessWidget {
  const _ServiceHours({
    required this.service,
    required this.rules,
    required this.season,
  });

  final String service;
  final List<HoursRule> rules;

  /// Which season these hours belong to. Stated because RIT publishes fall and
  /// summer separately and the difference is easy to be caught out by.
  final String season;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grouped = groupRulesByDay(rules);

    // One group per service, read as: service, season, days, then spans.
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The route marker. Decoration, so it carries no meaning that is
              // not also in the text.
              ExcludeSemantics(
                child: Container(width: 4, color: scheme.primary),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ServiceHeading(service: service, season: season),
                      const SizedBox(height: 14),
                      for (var i = 0; i < grouped.length; i++) ...[
                        if (i > 0) ...[
                          const SizedBox(height: 14),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _DaySpans(label: grouped[i].$1, rules: grouped[i].$2),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Service name, with the season pushed to the opposite edge.
class _ServiceHeading extends StatelessWidget {
  const _ServiceHeading({required this.service, required this.season});

  final String service;
  final String season;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final name = Text(_serviceLabel(service), style: text.titleMedium);
    final label = Text(
      season.toUpperCase(),
      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
    );

    // At a large text scale the two stop fitting on one line, so the season
    // drops underneath rather than being squeezed.
    //
    // Decided from the text scale alone rather than from a LayoutBuilder: this
    // sits inside an IntrinsicHeight, which cannot measure a LayoutBuilder and
    // throws rather than degrading.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [name, const SizedBox(height: 2), label],
      );
    }
    return Row(
      children: [
        Expanded(child: name),
        label,
      ],
    );
  }
}

/// One day caption, and every span that day holds.
class _DaySpans extends StatelessWidget {
  const _DaySpans({required this.label, required this.rules});

  final String label;
  final List<HoursRule> rules;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < rules.length; i++) ...[
          // A split shift stacks under one caption. No plus sign: it reads as
          // arithmetic, or as both spans running at once.
          if (i > 0) const _WavyBreak(),
          Text(
            '${_time(rules[i].opensAt)} to ${_time(rules[i].closesAt)}',
            textAlign: TextAlign.center,
            style: text.displayMedium?.copyWith(
              fontSize: 34,
              height: 1.15,
              fontVariations: Weights.medium,
              color: scheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}

/// The marker between two spans of one day. Decoration only: the caption above
/// already says which day, and each span states its own times.
class _WavyBreak extends StatelessWidget {
  const _WavyBreak();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 7,
        child: CustomPaint(
          painter: _WavyPainter(
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.55),
          ),
          size: const Size(double.infinity, 7),
        ),
      ),
    ),
  );
}

class _WavyPainter extends CustomPainter {
  const _WavyPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // A short wave in the middle, rather than a rule the full width, so it
    // separates the spans without looking like another divider.
    const period = 13.0;
    final width = size.width.clamp(0.0, 96.0);
    final left = (size.width - width) / 2;
    final middle = size.height / 2;

    final path = Path()..moveTo(left, middle);
    for (var x = 0.0; x < width; x += period) {
      path.relativeQuadraticBezierTo(period / 4, -middle, period / 2, 0);
      path.relativeQuadraticBezierTo(period / 4, middle, period / 2, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavyPainter old) => old.color != color;
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
    if (n.contains('turf') || n.contains('field')) {
      return Icons.sports_soccer_rounded;
    }
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
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
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
    final from = starts.isEmpty
        ? 6
        : (starts.reduce((a, b) => a < b ? a : b) ~/ 60);
    final to = ends.isEmpty
        ? 24
        : ((ends.reduce((a, b) => a > b ? a : b) + 59) ~/ 60);

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

    final rules = [...space.hours]
      ..sort(
        (a, b) => _weekOrder
            .indexOf(a.days.isEmpty ? '' : a.days.first)
            .compareTo(_weekOrder.indexOf(b.days.isEmpty ? '' : b.days.first)),
      );

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
                  child: Icon(
                    Icons.construction_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
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
            subtitle:
                '${room.machines} machine${room.machines == 1 ? '' : 's'}',
            accent: room.available > 0 ? semantic.open : semantic.closed,
            emphasis: room.available > 0
                ? RowEmphasis.normal
                : RowEmphasis.dimmed,
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
