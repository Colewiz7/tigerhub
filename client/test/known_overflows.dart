/// Layout overflows that exist today and are scheduled to be fixed.
///
/// golden_harness.dart fails any golden test that overflows by an amount not
/// listed here, and fails a listed test whose overflow has gone. The A+B
/// change that fixes an item deletes its entry in the same commit.
library;

class KnownOverflow {
  const KnownOverflow(this.pixels, this.fix);

  /// Measured overflow, one value per distinct overflow in the test.
  final List<double> pixels;

  /// The A+B item that removes it.
  final String fix;
}

/// Keyed by the exact test description.
const knownOverflows = <String, KnownOverflow>{
  // The map card strip Column (campus_map.dart:900) sits in a fixed-height
  // box, so 2x text overruns it vertically.
  'map screen 390x844 light 2.0x': KnownOverflow([24], 'A+B: map card strip fits at 2x text'),
  'map screen 390x844 dark 2.0x': KnownOverflow([24], 'A+B: map card strip fits at 2x text'),
  'map screen 430x932 light 2.0x': KnownOverflow([24], 'A+B: map card strip fits at 2x text'),
  'map screen 430x932 dark 2.0x': KnownOverflow([24], 'A+B: map card strip fits at 2x text'),
};
