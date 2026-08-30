/// What a post office service is doing right now.
///
/// The config carries the full picture: per service, per weekday, per season,
/// and a service can close over lunch and reopen. That is the right shape to
/// store and the wrong shape to read when you are standing outside wondering
/// whether to walk over.
///
/// So this answers the actual question in one line. It never replaces the full
/// table, which stays for planning the rest of the week.
///
/// Times are campus wall clock. A post office does not move when a laptop
/// does, so this uses [CampusTime] rather than the device clock, the same as
/// dining hours.
library;

import '../data/campus_time.dart';
import '../models/api_models.dart';

/// Where a service is in its day.
enum ServiceState {
  /// Open now.
  open,

  /// Closed now, but opening again later today. The lunch gap, mostly.
  closedUntilLater,

  /// Done for the day, or not open today at all.
  closedForDay,

  /// No rule covers this service in this season, so nothing can be claimed.
  unknown,
}

class TodaysHours {
  const TodaysHours({
    required this.service,
    required this.state,
    this.opensAt,
    this.closesAt,
    this.spans = const [],
  });

  final String service;
  final ServiceState state;

  /// The next opening, when [state] is not [ServiceState.open].
  final DateTime? opensAt;

  /// When the current span ends, while open.
  final DateTime? closesAt;

  /// Every span today, in order. A service closed over lunch has two.
  final List<({DateTime opens, DateTime closes})> spans;

  bool get isOpen => state == ServiceState.open;
}

const List<String> _weekdayNames = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

DateTime? _at(DateTime day, String clock) {
  final parts = clock.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return CampusTime.wall(day.year, day.month, day.day, hour, minute);
}

/// Resolve one service's rules into what it is doing at [now].
///
/// [rules] should already be filtered to the season in force. Rules for other
/// weekdays are ignored here rather than by the caller, so a caller cannot
/// forget.
TodaysHours todaysHours({
  required String service,
  required List<HoursRule> rules,
  required DateTime now,
}) {
  final today = CampusTime.dateOf(now);
  final weekday = _weekdayNames[CampusTime.fieldsOf(now).weekday - 1];

  final spans = <({DateTime opens, DateTime closes})>[];
  for (final rule in rules) {
    if (rule.service != service) continue;
    if (!rule.days.contains(weekday)) continue;
    final opens = _at(today, rule.opensAt);
    final closes = _at(today, rule.closesAt);
    if (opens == null || closes == null) continue;
    spans.add((opens: opens, closes: closes));
  }

  if (rules.every((r) => r.service != service)) {
    return TodaysHours(service: service, state: ServiceState.unknown);
  }

  spans.sort((a, b) => a.opens.compareTo(b.opens));

  final moment = now.toUtc();

  for (final span in spans) {
    if (!span.opens.isAfter(moment) && moment.isBefore(span.closes)) {
      return TodaysHours(
        service: service,
        state: ServiceState.open,
        closesAt: span.closes,
        spans: spans,
      );
    }
  }

  // Closed now. Is it coming back today, or done?
  for (final span in spans) {
    if (span.opens.isAfter(moment)) {
      return TodaysHours(
        service: service,
        state: ServiceState.closedUntilLater,
        opensAt: span.opens,
        spans: spans,
      );
    }
  }

  return TodaysHours(
    service: service,
    state: ServiceState.closedForDay,
    spans: spans,
  );
}

/// Every service this office runs, in the order the rules list them, so the
/// display order stays the config's decision rather than alphabetical.
List<String> servicesIn(List<HoursRule> rules) {
  final seen = <String>[];
  for (final rule in rules) {
    if (!seen.contains(rule.service)) seen.add(rule.service);
  }
  return seen;
}
