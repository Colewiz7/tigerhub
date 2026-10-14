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
  const KnownOverflow(this.file, this.overflows, this.fix);

  /// Basename of the test file that defines the test.
  final String file;
  final List<ExpectedOverflow> overflows;

  /// The A+B item that removes it.
  final String fix;
}

const _mapFile = 'map_screen_golden_test.dart';
const _stripFix = 'A+B: map card strip fits at 2x text. Until then these goldens '
    'deliberately show the overflow stripe: it is the documented baseline.';
// Two cards are visible in the strip, and each overflows.
const _strip = [ExpectedOverflow('lib/widgets/campus_map.dart:900', 'bottom', 24, count: 2)];

/// Keyed by the exact test description. The card strip Column
/// (campus_map.dart:900) sits in a fixed-height box, so 2x text overruns it.
const knownOverflows = <String, KnownOverflow>{
  'map screen 390x844 light 2.0x': KnownOverflow(_mapFile, _strip, _stripFix),
  'map screen 390x844 dark 2.0x': KnownOverflow(_mapFile, _strip, _stripFix),
  'map screen 430x932 light 2.0x': KnownOverflow(_mapFile, _strip, _stripFix),
  'map screen 430x932 dark 2.0x': KnownOverflow(_mapFile, _strip, _stripFix),
};
