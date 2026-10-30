/// Which visiting chefs are still worth listing.
library;

import 'dart:async';

import '../models/api_models.dart';
import 'campus_time.dart';
import 'dining_display_names.dart';
import 'dining_hidden.dart' show GroupPlace;
import 'sources/rit_chefs.dart' show locationKey;

const Duration chefGrace = Duration(minutes: 30);

// Chefs at places a hidden group hides. The id decides when the feed gave
// one, else the name does, through the same aliases the feed merge uses. A
// place nobody can place stays listed.
List<MenuItem> withoutHiddenChefs(Iterable<MenuItem> chefs, Iterable<GroupPlace> hiddenPlaces) => [
  for (final chef in chefs)
    if (!atHiddenPlace(chef.locationName, hiddenPlaces, id: chef.locationId)) chef,
];

bool atHiddenPlace(String locationName, Iterable<GroupPlace> hiddenPlaces, {int? id}) {
  if (hiddenPlaces.isEmpty) return false;
  if (id != null) return hiddenPlaces.any((p) => p.id == id);
  final key = locationKey(locationName);
  return hiddenPlaces.any((p) => locationKey(p.name) == key);
}

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
  return 'Next: ${[day, next.name, diningDisplayName(null, next.locationName)].where((part) => part.isNotEmpty).join(' · ')}';
}

/// Where a listed chef is in their slot.
enum ChefPhase {
  /// No time given, or a start with no end once started. Full strength.
  untimed,

  /// Inside the slot. Full strength.
  active,

  /// The slot has not started.
  upcoming,

  /// The slot is over but the chef is still listed for the grace window.
  ended;

  /// Shown muted: not on right now.
  bool get inactive => this == upcoming || this == ended;
}

// slot end on the same absolute clock as the start, past midnight when it wraps
DateTime? _slotEnd(MenuItem chef) {
  final start = chef.startsAt;
  var end = chef.endsAt;
  if (end == null) return null;
  if (start != null && end.isBefore(start)) {
    end = end.add(const Duration(days: 1));
  }
  return end.toUtc();
}

// The start minute is active and the end minute is not: [start, end).
ChefPhase chefPhase(MenuItem chef, {DateTime? now}) {
  final instant = (now ?? CampusTime.nowUtc()).toUtc();
  final start = chef.startsAt?.toUtc();
  final end = _slotEnd(chef);
  if (start == null && end == null) return ChefPhase.untimed;
  if (start != null && instant.isBefore(start)) return ChefPhase.upcoming;
  if (end != null && !instant.isBefore(end)) return ChefPhase.ended;
  return ChefPhase.active;
}

// the soonest moment any chef starts, ends or drops off, null when none will
DateTime? nextChefChange(Iterable<MenuItem> chefs, {DateTime? now}) {
  final instant = (now ?? CampusTime.nowUtc()).toUtc();
  DateTime? next;
  for (final chef in chefs) {
    for (final at in [chef.startsAt?.toUtc(), _slotEnd(chef), _cutoff(chef)]) {
      if (at == null || !instant.isBefore(at)) continue;
      if (next == null || at.isBefore(next)) next = at;
    }
  }
  return next;
}

/// One shot timer that fires at the next start, end or cutoff and arms the
/// one after it. Never ticks.
class ChefRearm {
  Timer? _timer;

  void arm(Iterable<MenuItem> chefs, void Function() onFire) {
    cancel();
    final next = nextChefChange(chefs);
    if (next == null) return;
    var wait = next.difference(CampusTime.nowUtc());
    // a clock that hasnt moved must not spin
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer = Timer(wait, () {
      onFire();
      arm(chefs, onFire);
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
