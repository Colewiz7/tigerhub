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

/// The next time [service] opens after [now], looking up to a week ahead. Null
/// when no rule in [rules] ever opens it.
DateTime? nextOpening({
  required String service,
  required List<HoursRule> rules,
  required DateTime now,
}) {
  final moment = now.toUtc();
  final fields = CampusTime.fieldsOf(moment);
  for (var ahead = 0; ahead <= 7; ahead++) {
    // calendar days, so a dst change cant skip one
    final day = DateTime.utc(fields.year, fields.month, fields.day + ahead);
    final weekday = _weekdayNames[day.weekday - 1];
    DateTime? first;
    for (final rule in rules) {
      if (rule.service != service || !rule.days.contains(weekday)) continue;
      final opens = _at(day, rule.opensAt);
      if (opens == null || !opens.isAfter(moment)) continue;
      if (first == null || opens.isBefore(first)) first = opens;
    }
    if (first != null) return first;
  }
  return null;
}

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

/// Minutes after midnight for an `HH:MM` clock, or null when it is not one.
int? clockMinutes(String clock) {
  final parts = clock.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

/// A clock in words: 7 AM, 4:30 PM, midnight. [minute] may run past 1440 for
/// a window that ends after midnight.
String clockLabel(int minute) {
  final m = minute % 1440;
  if (m == 0) return 'midnight';
  final hour = m ~/ 60;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final mm = m % 60;
  final suffix = hour < 12 ? 'AM' : 'PM';
  return mm == 0 ? '$h12 $suffix' : '$h12:${mm.toString().padLeft(2, '0')} $suffix';
}

enum ChangeKind { opens, closes, closedToday }

/// What happens next at a place with these [spans] today, at [nowMinute]
/// campus minutes after midnight. Spans that touch count as one, so a pool
/// with back to back sessions says when it really closes.
({ChangeKind kind, int? minute}) nextChange(
  List<({String opens, String closes})> spans,
  int nowMinute,
) {
  final windows = <({int opens, int closes})>[];
  for (final span in spans) {
    final opens = clockMinutes(span.opens);
    var closes = clockMinutes(span.closes);
    if (opens == null || closes == null) continue;
    if (closes <= opens) closes += 1440;
    windows.add((opens: opens, closes: closes));
  }
  windows.sort((a, b) => a.opens.compareTo(b.opens));
  final merged = <({int opens, int closes})>[];
  for (final w in windows) {
    if (merged.isNotEmpty && w.opens <= merged.last.closes) {
      final last = merged.removeLast();
      merged.add((opens: last.opens, closes: w.closes > last.closes ? w.closes : last.closes));
    } else {
      merged.add(w);
    }
  }
  for (final w in merged) {
    if (nowMinute < w.opens) return (kind: ChangeKind.opens, minute: w.opens);
    if (nowMinute < w.closes) return (kind: ChangeKind.closes, minute: w.closes);
  }
  return (kind: ChangeKind.closedToday, minute: null);
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
