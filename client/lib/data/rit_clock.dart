/// The one source of "now" for anything that depends on the campus calendar.
///
/// Every campus schedule is America/New_York wall clock, never the device zone,
/// so code that asks "is it open", "is this today" or "what day is it" goes
/// through here (usually via `CampusTime`) and tests can pin the instant.
///
/// Elapsed time (cache age, cadence, "5m ago") does not need this: a duration
/// is the same in every zone, so `DateTime.now()` is correct there.
library;

import 'package:flutter/foundation.dart';

class RitClock {
  const RitClock._();

  static DateTime Function() _source = DateTime.now;

  /// The current instant, in UTC.
  static DateTime nowUtc() => _source().toUtc();

  /// Pin the clock in a test. Pair with [reset] in a tearDown.
  @visibleForTesting
  static void pin(DateTime instant) => _source = () => instant;

  @visibleForTesting
  static void reset() => _source = DateTime.now;
}
