/// Layout overflows that exist today and are scheduled to be fixed.
///
/// golden_harness.dart fails any golden test whose overflows differ from its
/// entry here in source line, edge, size (0.5px) or count, including a test
/// with no entry that overflows at all. The A+B change that fixes an item
/// deletes its entry in the same commit.
library;

class ExpectedOverflow {
  const ExpectedOverflow(this.where, this.side, this.pixels, {this.count = 1});

  /// lib/ source line of the widget that overflows, as the harness reports it.
  final String where;

  /// Edge it overflows: left, right, top or bottom.
  final String side;
  final double pixels;

  /// How many distinct render objects overflow like this.
  final int count;

  @override
  String toString() => '${pixels}px on the $side at $where';
}

class KnownOverflow {
  const KnownOverflow(this.overflows, this.fix);

  final List<ExpectedOverflow> overflows;

  /// The A+B item that removes it.
  final String fix;
}

/// Keyed by (test file basename, exact test description): the same description
/// in another file does not match. Empty: nothing overflows today.
const knownOverflows = <(String, String), KnownOverflow>{};
