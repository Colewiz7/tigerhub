/// Resolve the TigerCenter hours recurrence model into concrete daily spans.
///
/// Ported from `backend/app/hours.py`, behaviour for behaviour.
///
/// TigerCenter does not publish a list of days. It publishes, per location, a
/// set of `events`, each being a term long window (startDate to endDate) plus a
/// weekday mask plus a daily open and close time, plus dated `exceptions` that
/// override that window on specific dates.
///
/// Everything here turns that into concrete open/close spans per date. An
/// "is it open right now" boolean and the next transition time are derived from
/// those spans.
///
/// Overnight spans (Midnight Oil closes at 1 a.m.) are represented by
/// [Span.closesNextDay], meaning the close time belongs to the following
/// calendar day.
library;

import 'campus_time.dart';

const List<String> weekdays = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

/// A time of day, with no date attached.
class Clock implements Comparable<Clock> {
  const Clock(this.hour, this.minute, this.second);

  final int hour;
  final int minute;
  final int second;

  int get _asSeconds => hour * 3600 + minute * 60 + second;

  @override
  int compareTo(Clock other) => _asSeconds.compareTo(other._asSeconds);

  bool operator <=(Clock other) => _asSeconds <= other._asSeconds;

  @override
  bool operator ==(Object other) =>
      other is Clock && other._asSeconds == _asSeconds;

  @override
  int get hashCode => _asSeconds;

  @override
  String toString() => '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}';
}

/// One concrete open period on one calendar date.
class Span {
  const Span({
    required this.serviceDate,
    required this.opensAt,
    required this.closesAt,
    this.closesNextDay = false,
    this.menuTypes = const [],
    this.sourceEventId,
    this.isException = false,
  });

  /// A UTC midnight marking the campus calendar date this span serves.
  final DateTime serviceDate;
  final Clock opensAt;
  final Clock closesAt;
  final bool closesNextDay;
  final List<String> menuTypes;
  final int? sourceEventId;
  final bool isException;

  DateTime startInstant() => CampusTime.wall(
        serviceDate.year,
        serviceDate.month,
        serviceDate.day,
        opensAt.hour,
        opensAt.minute,
        opensAt.second,
      );

  DateTime endInstant() {
    final day = closesNextDay
        ? serviceDate.add(const Duration(days: 1))
        : serviceDate;
    return CampusTime.wall(
      day.year,
      day.month,
      day.day,
      closesAt.hour,
      closesAt.minute,
      closesAt.second,
    );
  }

  bool contains(DateTime moment) {
    final m = moment.toUtc();
    return !startInstant().isAfter(m) && m.isBefore(endInstant());
  }
}

/// What the client actually renders: a boolean and the next transition.
class OpenState {
  const OpenState({
    required this.isOpen,
    this.opensAt,
    this.closesAt,
    this.nextTransition,
    this.spansToday = const [],
  });

  final bool isOpen;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime? nextTransition;
  final List<Span> spansToday;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parts = value.split('-');
  if (parts.length < 3) return null;
  return DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

Clock? parseClock(Object? value) {
  if (value is! String || value.isEmpty) return null;
  // TigerCenter sends "HH:MM:SS". Tolerate a missing seconds component.
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.first == null) return null;
  var hour = parts[0]!;
  var minute = parts.length > 1 ? (parts[1] ?? 0) : 0;
  var second = parts.length > 2 ? (parts[2] ?? 0) : 0;
  // A 24:00:00 close means end of day, which a wall clock cannot hold.
  if (hour >= 24) {
    hour = 23;
    minute = 59;
    second = 59;
  }
  return Clock(hour, minute, second);
}

/// Does this event or exception apply on the given campus date?
bool covers(Map<String, dynamic> entry, DateTime day) {
  final start = _parseDate(entry['startDate']);
  final end = _parseDate(entry['endDate']);
  if (start != null && day.isBefore(start)) return false;
  // `infinite` events have no meaningful end date.
  if (end != null && entry['infinite'] != true && day.isAfter(end)) return false;
  final days = (entry['daysOfWeek'] as List<dynamic>? ?? const [])
      .map((d) => d.toString())
      .toSet();
  return days.contains(weekdays[day.weekday - 1]);
}

Span? _spanFrom(Map<String, dynamic> entry, DateTime day, bool isException) {
  final opens = parseClock(entry['startTime']);
  final closes = parseClock(entry['endTime']);
  if (opens == null || closes == null) return null;
  // A close time at or before the open time means the span runs past midnight.
  final crosses = closes <= opens;
  return Span(
    serviceDate: day,
    opensAt: opens,
    closesAt: closes,
    closesNextDay: crosses,
    menuTypes: [
      for (final m in entry['menuTypes'] as List<dynamic>? ?? const [])
        m.toString(),
    ],
    sourceEventId: entry['id'] as int?,
    isException: isException,
  );
}

/// Resolve one location's events into concrete spans for one date.
///
/// An exception that matches the date replaces its parent event's span for that
/// date. An exception with `open: false` closes the location outright.
List<Span> resolveDay(List<dynamic> events, DateTime day) {
  final spans = <Span>[];

  for (final raw in events) {
    if (raw is! Map<String, dynamic>) continue;

    final exceptions = [
      for (final e in raw['exceptions'] as List<dynamic>? ?? const [])
        if (e is Map<String, dynamic> && covers(e, day)) e,
    ];

    if (exceptions.isNotEmpty) {
      for (final exception in exceptions) {
        // open=false is a closure, so the parent span is dropped and nothing
        // replaces it.
        if (exception['open'] == false) continue;
        final span = _spanFrom(exception, day, true);
        if (span != null) spans.add(span);
      }
      continue;
    }

    if (covers(raw, day)) {
      final span = _spanFrom(raw, day, false);
      if (span != null) spans.add(span);
    }
  }

  spans.sort((a, b) {
    final byOpen = a.opensAt.compareTo(b.opensAt);
    return byOpen != 0 ? byOpen : a.closesAt.compareTo(b.closesAt);
  });
  return spans;
}

/// Resolve a contiguous window of dates.
List<Span> resolveRange(List<dynamic> events, DateTime start, int days) => [
      for (var offset = 0; offset < days; offset++)
        ...resolveDay(events, start.add(Duration(days: offset))),
    ];

String dateKey(DateTime day) => '${day.year}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Derive open/closed plus the next transition from resolved spans.
///
/// Yesterday's spans are considered too, because an overnight span that opened
/// yesterday can still be running now.
OpenState openState(Map<String, List<Span>> spansByDate, DateTime moment) {
  final today = CampusTime.dateOf(moment);
  final yesterday = today.subtract(const Duration(days: 1));

  final candidates = <Span>[
    ...?spansByDate[dateKey(yesterday)],
    ...?spansByDate[dateKey(today)],
  ];

  for (final span in candidates) {
    if (span.contains(moment)) {
      return OpenState(
        isOpen: true,
        opensAt: span.startInstant(),
        closesAt: span.endInstant(),
        nextTransition: span.endInstant(),
        spansToday: spansByDate[dateKey(today)] ?? const [],
      );
    }
  }

  // Closed. Find the next opening across the resolved window.
  final upcoming = <Span>[
    for (final spans in spansByDate.values)
      for (final s in spans)
        if (s.startInstant().isAfter(moment.toUtc())) s,
  ]..sort((a, b) => a.startInstant().compareTo(b.startInstant()));

  final next = upcoming.isEmpty ? null : upcoming.first.startInstant();
  return OpenState(
    isOpen: false,
    opensAt: next,
    closesAt: null,
    nextTransition: next,
    spansToday: spansByDate[dateKey(today)] ?? const [],
  );
}

Map<String, List<Span>> groupByDate(List<Span> spans) {
  final grouped = <String, List<Span>>{};
  for (final span in spans) {
    grouped.putIfAbsent(dateKey(span.serviceDate), () => []).add(span);
  }
  return grouped;
}
