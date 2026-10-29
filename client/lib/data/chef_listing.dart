/// Which visiting chefs are still worth listing.
library;

import '../models/api_models.dart';
import 'campus_time.dart';

const Duration chefGrace = Duration(minutes: 30);

// null when no end is known
DateTime? _cutoff(MenuItem chef) {
  final start = chef.startsAt;
  var end = chef.endsAt;
  if (end == null) return null;
  // end before start means the slot runs past midnight
  if (start != null && end.isBefore(start)) {
    end = end.add(const Duration(days: 1));
  }
  return end.toUtc().add(chefGrace);
}

// a chef with no end stays all day
bool chefStillListed(MenuItem chef, {DateTime? now}) {
  final cutoff = _cutoff(chef);
  if (cutoff == null) return true;
  return (now ?? CampusTime.nowUtc()).toUtc().isBefore(cutoff);
}

// the soonest moment a listed chef drops off, null when none will
DateTime? nextChefCutoff(Iterable<MenuItem> chefs, {DateTime? now}) {
  final instant = (now ?? CampusTime.nowUtc()).toUtc();
  DateTime? next;
  for (final chef in chefs) {
    final cutoff = _cutoff(chef);
    if (cutoff == null || !instant.isBefore(cutoff)) continue;
    if (next == null || cutoff.isBefore(next)) next = cutoff;
  }
  return next;
}

List<MenuItem> listedChefs(Iterable<MenuItem> chefs, {DateTime? now}) {
  final instant = now ?? CampusTime.nowUtc();
  return [
    for (final chef in chefs)
      if (chefStillListed(chef, now: instant)) chef,
  ];
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// all of the chefs the feed lists for today have ended
bool chefsAllEnded(Iterable<MenuItem> chefs, {DateTime? now}) => chefs.isNotEmpty && listedChefs(chefs, now: now).isEmpty;

// "Next: Tomorrow · Chef Lin · Gracie's", dates on the campus calendar
String nextChefLine(UpcomingChef next, DateTime today) {
  final days = next.date.difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final day = switch (days) {
    1 => 'Tomorrow',
    _ => '${_weekdays[next.date.weekday - 1]}, ${_months[next.date.month - 1]} ${next.date.day}',
  };
  return 'Next: ${[day, next.name, next.locationName].where((part) => part.isNotEmpty).join(' · ')}';
}
