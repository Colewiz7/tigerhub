/// A 48pt hit region around a smaller visual.
///
/// The spec: visual size may be smaller, the hit area never is. Flutter only
/// hit-tests inside a parent's layout box, so the region is a real 48 tall box
/// with the visual centered in it. Taps anywhere in the box land on [onTap];
/// the visual keeps its own state layer and semantics.
library;

import 'package:flutter/material.dart';

class TouchTarget extends StatelessWidget {
  const TouchTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.alignment = Alignment.center,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// Where the visual sits in the box, for a visual that hugs one edge.
  final AlignmentGeometry alignment;

  /// The smallest touch target.
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // The visual already carries the button semantics and label.
      excludeFromSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: size, minWidth: size),
        child: Align(
          alignment: alignment,
          widthFactor: 1,
          heightFactor: 1,
          child: child,
        ),
      ),
    );
  }
}
