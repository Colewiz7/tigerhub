/// A snapshot has to be invalidated by what it asked for, not only by its age.
///
/// I added the Workday time clocks and the kiosks still did not show up.
/// Both halves of the app were correct: the category was registered and the
/// scraper would have fetched it. The snapshot on disk was 20 minutes old
/// against a 12 hour cadence, so nothing refetched, and the new places were
/// due to appear the following morning.
///
/// Age answers "has this data gone off". It cannot answer "does this data
/// still contain what the app now asks for", and that is the question that
/// matters the moment a category is added.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/data/sources/campus_places.dart';

void main() {
  test('the fingerprint covers both halves of the request set', () {
    // A kind registered without its parent is never fetched. A parent fetched
    // without the kind registered has its points parsed and thrown away. Both
    // have happened, so both must move the fingerprint.
    final fingerprint = campusPlacesFingerprint;

    expect(fingerprint, contains('parents:'));
    expect(fingerprint, contains('kinds:'));
    for (final parent in placeParents) {
      expect(fingerprint, contains('$parent'));
    }
    for (final kind in placeKinds.keys) {
      expect(fingerprint, contains('$kind'));
    }
  });

  test('it is stable across reads', () {
    // It is compared against a string on disk, so an unstable one would
    // refetch every launch and hammer maps.rit.edu. docs/notes.md 6.
    expect(campusPlacesFingerprint, campusPlacesFingerprint);
  });

  test('it names the categories this change added', () {
    // Guards the specific regression: these are the ids that were invisible.
    for (final id in [
      199, 527, 236, 211, 528, 279, 87, 83, 452, 449, 440, 183, 187,
    ]) {
      expect(placeKinds.containsKey(id), isTrue, reason: 'kind $id');
      expect(campusPlacesFingerprint, contains('$id'));
    }
    // A kind whose parent is never fetched is dead weight, and nothing else
    // would say so. 39 and 31 are the two parents these additions needed.
    expect(placeParents, contains(39));
    expect(placeParents, contains(31));
  });
}
