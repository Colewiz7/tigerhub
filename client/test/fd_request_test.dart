/// What the app asks FD MealPlanner for.
///
/// This is a scraping-ethics guard as much as a correctness one. docs/notes.md 6
/// says cache aggressively and never scrape more than needed, and this request
/// has already gone wrong twice in ways that cost RIT's vendor real bandwidth
/// and cost the user a working menu:
///
///   - `startDate` and `endDate` were sent empty, so every fetch pulled a
///     whole month. Measured at Gracie's: 25.9 MB and 6.9s against 1.0 MB and
///     0.6s for a single day, and Gracie's publishes two meal periods, so one
///     day's dishes were going to cost about 52 MB.
///   - the scraper asked every location for period 8, FD's "All Day", which
///     most locations do not publish. Asking for a period a location does not
///     have returns an empty result rather than an error, so most locations
///     silently had no menu at all. Gracie's went from 0 dishes to 6,252.
///
/// Neither failure throws, and neither is visible in the UI beyond a menu that
/// looks empty, so nothing else would catch a regression.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/fd_menus.dart';

void main() {
  test('a menu request asks for exactly one day', () {
    final url = fdUrl(20, 10, 10, 3, DateTime(2026, 8, 30), '2026-08-30');

    expect(url, contains('startDate=2026-08-30'));
    expect(url, contains('endDate=2026-08-30'));
    expect(
      url,
      isNot(contains('startDate=&')),
      reason: 'an empty window is how the 26x month-long fetch happened',
    );
    expect(url, isNot(contains('endDate=&')));
  });

  test('the window is a single day, not a range', () {
    // Same date on both ends. A range would quietly scale the payload by its
    // length, which is the failure that already happened.
    final url = fdUrl(20, 10, 10, 3, DateTime(2026, 9, 1), '2026-09-01');
    final start = RegExp(r'startDate=([\d-]*)').firstMatch(url)!.group(1);
    final end = RegExp(r'endDate=([\d-]*)').firstMatch(url)!.group(1);

    expect(start, isNotEmpty);
    expect(start, end);
  });

  test('the meal period is a parameter, never a hardcoded All Day', () {
    // Period 8 is FD's "All Day". Baking it in is what left most locations
    // with no menu, because most of them do not publish it.
    final url = fdUrl(20, 14, 4, 3, DateTime(2026, 8, 30), '2026-08-30');
    expect(url, contains('mealPeriodId=3'));
  });

  test('meal periods are asked for per location', () {
    expect(fdMealPeriodsUrl, contains('LocationId={location}'));
  });

  test('an account id that differs from the location id is kept distinct', () {
    // RITZ, The Commons and The College Grind have an accountId that is not
    // their locationId. Collapsing the two served RITZ Gracie's menu, and
    // Gracie's allergens with it.
    final url = fdUrl(20, 4, 14, 3, DateTime(2026, 8, 30), '2026-08-30');
    expect(url, contains('accountId=4'));
    expect(url, contains('locationId=14'));
  });
}
