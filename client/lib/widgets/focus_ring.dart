/// The keyboard focus ring.
library;

import 'package:flutter/material.dart';

/// The keyboard focus ring: 2px, [ColorScheme.primary], 2px clear of the
/// element. It is painted around the child without taking any room, so
/// focusing moves nothing. The ring box is the child inflated by 4px and its
/// border paints inside that box: the outer 2px is the ring and the 2px inside
/// it is the gap.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.radius, required this.builder});

  /// The child's corner radius. The ring's is this plus the 4px.
  final double radius;

  /// Builds the focusable child, handing it the callback that reports focus.
  final Widget Function(ValueChanged<bool> onFocusChange) builder;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // For the keyboard only. A tap focuses the element too, and a ring after
    // every tap would be noise.
    final show =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.builder((focused) => setState(() => _focused = focused)),
        if (show)
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('focus-ring'),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(widget.radius + 4),
                    side: BorderSide(
                      width: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
