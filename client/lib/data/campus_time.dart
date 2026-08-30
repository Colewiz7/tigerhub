/// Campus wall clock time, which is always America/New_York.
///
/// The backend got this from Python's tzdata. Dart has no named timezone
/// database without pulling in the `timezone` package, and US Eastern's rule is
/// small, fixed, and easy to test, so it is implemented here instead of taking
/// a dependency for one zone.
///
/// **This deliberately does not use the device's local time.** A student home
/// for break still wants RIT's hours, not their own, and a laptop that travels
/// would otherwise silently shift every opening time.
///
/// Rule, unchanged in the US since 2007:
///   DST begins  second Sunday in March,   02:00 local standard  (07:00 UTC)
///   DST ends    first Sunday in November, 02:00 local daylight  (06:00 UTC)
///
/// If Congress ever makes DST permanent this is the one file that has to
/// change, which is the reason it is one file.
library;

const Duration _standard = Duration(hours: -5); // EST
const Duration _daylight = Duration(hours: -4); // EDT

class CampusTime {
  const CampusTime._();

  /// UTC instant of the Nth [weekday] in [month], where weekday is
  /// `DateTime.sunday` etc. and [n] is 1-based.
  static DateTime _nthWeekday(int year, int month, int weekday, int n) {
    final first = DateTime.utc(year, month, 1);
    var day = 1 + (weekday - first.weekday + 7) % 7;
    day += (n - 1) * 7;
    return DateTime.utc(year, month, day);
  }

  /// Is [instant] (a UTC instant) inside Eastern Daylight Time?
  static bool isDaylight(DateTime instant) {
    final utc = instant.toUtc();
    final start = _nthWeekday(utc.year, 3, DateTime.sunday, 2)
        .add(const Duration(hours: 7));
    final end = _nthWeekday(utc.year, 11, DateTime.sunday, 1)
        .add(const Duration(hours: 6));
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  static Duration offsetAt(DateTime instant) =>
      isDaylight(instant) ? _daylight : _standard;

  /// Turn a campus wall clock reading into the UTC instant it names.
  ///
  /// The offset depends on the instant, and the instant depends on the offset,
  /// so this guesses with the daylight offset and corrects once. That converges
  /// everywhere except inside the two ambiguous hours at a transition, where it
  /// settles on a consistent choice rather than throwing.
  static DateTime wall(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) {
    final naive = DateTime.utc(year, month, day, hour, minute, second);
    var instant = naive.subtract(_daylight);
    if (!isDaylight(instant)) {
      instant = naive.subtract(_standard);
    }
    return instant;
  }

  /// Campus wall clock fields for a UTC instant, as a DateTime whose component
  /// getters read as campus local time. Never use this for arithmetic.
  static DateTime fieldsOf(DateTime instant) =>
      instant.toUtc().add(offsetAt(instant));

  static DateTime nowUtc() => DateTime.now().toUtc();

  /// The campus calendar date of a UTC instant.
  static DateTime dateOf(DateTime instant) {
    final f = fieldsOf(instant);
    return DateTime.utc(f.year, f.month, f.day);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// ISO 8601 with the explicit campus offset, matching what the server sent:
  /// `2026-08-31T07:30:00-04:00`.
  static String format(DateTime instant) {
    final f = fieldsOf(instant);
    final offset = offsetAt(instant);
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    return '${f.year}-${_two(f.month)}-${_two(f.day)}'
        'T${_two(f.hour)}:${_two(f.minute)}:${_two(f.second)}'
        '$sign${_two(abs.inHours)}:${_two(abs.inMinutes % 60)}';
  }

  /// `2026-08-31`, the campus calendar date, which is what the TigerCenter
  /// `?date=` parameter expects.
  static String formatDate(DateTime instant) {
    final f = fieldsOf(instant);
    return '${f.year}-${_two(f.month)}-${_two(f.day)}';
  }
}
