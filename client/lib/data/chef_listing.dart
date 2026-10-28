/// Which visiting chefs are still worth listing.
library;

import '../models/api_models.dart';
import 'campus_time.dart';

const Duration chefGrace = Duration(minutes: 30);

// a chef with no end stays all day
bool chefStillListed(MenuItem chef, {DateTime? now}) {
  final start = chef.startsAt;
  var end = chef.endsAt;
  if (end == null) return true;
  // end before start means the slot runs past midnight
  if (start != null && end.isBefore(start)) {
    end = end.add(const Duration(days: 1));
  }
  final instant = (now ?? CampusTime.nowUtc()).toUtc();
  return instant.isBefore(end.toUtc().add(chefGrace));
}

List<MenuItem> listedChefs(Iterable<MenuItem> chefs, {DateTime? now}) {
  final instant = now ?? CampusTime.nowUtc();
  return [
    for (final chef in chefs)
      if (chefStillListed(chef, now: instant)) chef,
  ];
}
