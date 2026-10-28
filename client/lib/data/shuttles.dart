/// Campus shuttle service windows, by where you live.
///
/// RIT publishes hours of operation per route, not departures, so nothing here
/// can say when the next bus comes. The table is assets/config/shuttles.json,
/// copied from RIT's schedule page with its date.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../services/todays_hours.dart';

enum ShuttleDays { weekday, weekend, breaks, holiday }

class ShuttleRoute {
  const ShuttleRoute({
    required this.number,
    required this.name,
    required this.days,
    this.start,
    this.end,
    this.note,
  });

  final int number;
  final String name;
  final ShuttleDays days;

  /// Minutes after campus midnight. [end] is past 1440 when the route runs
  /// over midnight.
  final int? start;
  final int? end;

  /// Shown in place of hours when a route has none of its own.
  final String? note;

  String get hours {
    if (note != null || start == null || end == null) return note ?? '';
    return '${_fullClock(start!)}–${_fullClock(end!)}';
  }

  // 7:00 AM, the way the schedule page writes it
  static String _fullClock(int minute) {
    final m = minute % 1440;
    final hour = m ~/ 60;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${(m % 60).toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
  }
}

/// Where a home area's service is today.
enum ShuttleState { before, running, done, none }

class ShuttleWindow {
  const ShuttleWindow({required this.state, this.routes = 0, this.minute});

  final ShuttleState state;

  /// Routes still to run or running.
  final int routes;

  /// First start before service, last end while running.
  final int? minute;
}

class ShuttleSchedule {
  const ShuttleSchedule({
    required this.sourceUrl,
    required this.lastVerified,
    required this.areas,
  });

  final String sourceUrl;
  final String lastVerified;
  final Map<String, List<ShuttleRoute>> areas;

  static final ValueNotifier<ShuttleSchedule?> current = ValueNotifier(null);
  static Future<ShuttleSchedule?>? _loading;

  static Future<ShuttleSchedule?> load([AssetBundle? bundle]) {
    if (current.value != null) return Future.value(current.value);
    return _loading ??= _read(bundle ?? rootBundle).then((schedule) {
      _loading = null;
      if (schedule != null) current.value = schedule;
      return schedule;
    });
  }

  static Future<ShuttleSchedule?> _read(AssetBundle bundle) async {
    try {
      return parse(jsonDecode(await bundle.loadString('assets/config/shuttles.json')) as Map<String, dynamic>);
    } catch (_) {
      // no table means no shuttle answer, never a crash
      return null;
    }
  }

  @visibleForTesting
  static void overrideForTesting(ShuttleSchedule? schedule) => current.value = schedule;

  static ShuttleSchedule parse(Map<String, dynamic> json) {
    final byNumber = <int, ShuttleRoute>{};
    for (final raw in json['routes'] as List<dynamic>) {
      final route = raw as Map<String, dynamic>;
      final start = clockMinutes(route['starts_at'] as String);
      var end = clockMinutes(route['ends_at'] as String);
      if (start != null && end != null && end <= start) end += 1440;
      final number = route['number'] as int;
      byNumber[number] = ShuttleRoute(
        number: number,
        name: route['name'] as String,
        days: ShuttleDays.values.byName(route['days'] as String),
        start: start,
        end: end,
      );
    }
    return ShuttleSchedule(
      sourceUrl: json['source_url'] as String,
      lastVerified: json['last_verified'] as String,
      areas: {
        for (final entry in (json['areas'] as Map<String, dynamic>).entries)
          entry.key: [
            for (final number in entry.value as List<dynamic>)
              if (byNumber[number as int] != null) byNumber[number]!,
          ],
      },
    );
  }

  bool covers(String? area) => area != null && areas.containsKey(area);

  /// Labor Day 2026 ran a reduced holiday service, the same for every area.
  static bool isHoliday(DateTime date) => date.year == 2026 && date.month == 9 && date.day == 7;

  static const List<ShuttleRoute> _holidayRoutes = [
    ShuttleRoute(number: 1, name: 'RIT RTS Connection (Holiday)', days: ShuttleDays.holiday, note: 'See the holiday timetable'),
    ShuttleRoute(number: 14, name: 'Campus & Inn Break Shuttle', days: ShuttleDays.holiday, start: 440, end: 1446),
  ];

  /// The routes that run on the campus calendar [date].
  List<ShuttleRoute> routesOn(String? area, DateTime date) {
    if (isHoliday(date)) return _holidayRoutes;
    final weekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    return [
      for (final route in areas[area] ?? const <ShuttleRoute>[])
        if (route.days == (weekend ? ShuttleDays.weekend : ShuttleDays.weekday)) route,
    ];
  }

  /// Today's service from [area] at the campus wall clock [now]: how many
  /// routes are still to run, and until when. A route that ran over midnight
  /// from yesterday still counts until it ends.
  ShuttleWindow windowAt(String? area, DateTime now) {
    final minute = now.hour * 60 + now.minute;
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final windows = <({int start, int end})>[
      for (final route in routesOn(area, yesterday))
        if (route.start != null && route.end != null && route.end! > 1440) (start: route.start! - 1440, end: route.end! - 1440),
      for (final route in routesOn(area, today))
        if (route.start != null && route.end != null) (start: route.start!, end: route.end!),
    ];
    if (windows.isEmpty) return const ShuttleWindow(state: ShuttleState.none);
    final ahead = [for (final w in windows) if (w.end > minute) w];
    if (ahead.isEmpty) return const ShuttleWindow(state: ShuttleState.done);
    final running = ahead.any((w) => w.start <= minute);
    if (!running) {
      final first = ahead.map((w) => w.start).reduce((a, b) => a < b ? a : b);
      return ShuttleWindow(state: ShuttleState.before, routes: ahead.length, minute: first);
    }
    // follow service with no gap, a 5 AM route isnt tonights
    ahead.sort((a, b) => a.start.compareTo(b.start));
    var until = minute;
    var routes = 0;
    for (final w in ahead) {
      if (w.start > until) break;
      routes++;
      if (w.end > until) until = w.end;
    }
    return ShuttleWindow(state: ShuttleState.running, routes: routes, minute: until);
  }
}
