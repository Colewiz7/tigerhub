/// How the Today grid picks its column count.
///
/// Width alone spread the cards into one wide row with a band of dead space
/// underneath, and with four cards and three columns it stranded the fourth
/// alone while there was room beside it. Cole's words: "it spread out
/// horizontally when there's space below".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tigerhub/home_screen.dart';

void main() {
  // The four default cards: dining, events, chefs, housing.
  const cards = 4;

  test('a tall wide window packs two by two rather than three and a widow', () {
    // 3 columns would put one card alone on its own row with two empty cells
    // beside it. 2 columns fills both rows.
    expect(homeGridColumns(1500, 1200, cards), 2);
  });

  test('a short wide window still uses the width', () {
    // Not enough height for two rows of full size cards, so spreading out is
    // the right answer rather than squashing them.
    expect(homeGridColumns(1900, 620, cards), greaterThan(2));
  });

  test('a narrow window stays single column', () {
    expect(homeGridColumns(700, 1200, cards), 1);
  });

  test('never exceeds what the width can carry', () {
    // Even with unlimited height, cards must not become slivers.
    for (final width in [700.0, 1000.0, 1500.0, 2400.0]) {
      final columns = homeGridColumns(width, 4000, cards);
      expect(columns, lessThanOrEqualTo(4));
      expect(columns, greaterThanOrEqualTo(1));
    }
  });

  test('a single card never splits into columns', () {
    expect(homeGridColumns(2400, 1200, 1), 1);
  });

  test('handles a degenerate viewport without dividing by zero', () {
    expect(homeGridColumns(1500, 0, cards), 1);
    expect(homeGridColumns(1500, -50, cards), 1);
  });

  test('six cards prefer a full last row too', () {
    // 4 columns leaves two empty cells; 3 columns fills both rows.
    final columns = homeGridColumns(1900, 1200, 6);
    expect(columns * (6 / columns).ceil() - 6, 0,
        reason: 'the last row was left ragged when it did not need to be');
  });
}
