/// RIT FoodShare, the free food pantry: weekly hours and today's open state.
///
/// The hours live in this one table. RIT has changed them before and holiday
/// and summer hours differ, so the row says they may change and links to the
/// source page. Times are campus wall clock, never the device's.
library;

import 'campus_time.dart';

const foodShareSourceUrl = 'https://www.rit.edu/lead/rit-foodshare';
const foodShareLastVerified = '2026-11-06';
const foodShareAddress = '113 Kimball Drive, Riverknoll Apartments';
const foodShareLabel = 'FoodShare';
const foodShareKind = 'Free food pantry';
const foodShareNote = 'Hours may change';

/// Open and close hour (24 hour clock) by `DateTime.weekday`, 1 is Monday.
/// A day that is missing is closed.
const foodShareHours = <int, ({int opens, int closes})>{
  DateTime.monday: (opens: 13, closes: 19),
  DateTime.tuesday: (opens: 13, closes: 19),
  DateTime.wednesday: (opens: 13, closes: 19),
  DateTime.thursday: (opens: 13, closes: 19),
  DateTime.saturday: (opens: 13, closes: 17),
};

enum FoodSharePhase { open, opensLater, closed }

class FoodShareStatus {
  const FoodShareStatus(this.phase, this.text);

  final FoodSharePhase phase;

  /// "Open until 7 PM", "Opens 1 PM" or "Closed today".
  final String text;

  bool get isOpen => phase == FoodSharePhase.open;
}

String _clock(int hour24) {
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour ${hour24 < 12 ? 'AM' : 'PM'}';
}

/// Today's state at [instant], read on the campus calendar. Opens on the hour
/// it opens and is closed on the hour it closes.
FoodShareStatus foodShareStatusAt(DateTime instant) {
  final now = CampusTime.fieldsOf(instant);
  final today = foodShareHours[now.weekday];
  if (today == null) return const FoodShareStatus(FoodSharePhase.closed, 'Closed today');
  if (now.hour < today.opens) {
    return FoodShareStatus(FoodSharePhase.opensLater, 'Opens ${_clock(today.opens)}');
  }
  if (now.hour < today.closes) {
    return FoodShareStatus(FoodSharePhase.open, 'Open until ${_clock(today.closes)}');
  }
  return const FoodShareStatus(FoodSharePhase.closed, 'Closed today');
}

/// Words that find the row in the Dining search box.
bool foodShareMatches(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return foodShareLabel.toLowerCase().contains(q) ||
      foodShareKind.toLowerCase().contains(q) ||
      'pantry'.contains(q) ||
      'free food'.contains(q);
}
