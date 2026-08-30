/// A short themed cover shown while a tab comes up.
///
/// Cole: switching pages "looks weird", and wanted a loading screen that
/// blocks out the background rather than the content assembling in view.
///
/// A note on the tension, because it is real: CLAUDE.md 3.1 says paint from
/// cache instantly and never show a cold-start spinner, and the motion spec's
/// first acceptance check is that a warm cache shows no spinner at all. This
/// deliberately adds a beat that the data does not need. It is kept short, and
/// it is one constant to tune, so the cost is visible rather than buried.
///
/// It earns its place on the Map tab, which is genuinely doing work on first
/// open: the geometry build is about 14ms and the canvas lays out from cold,
/// so without a cover you watch it assemble.
library;

import 'package:flutter/material.dart';

import 'arc_progress.dart';

class PageVeil extends StatefulWidget {
  const PageVeil({super.key, required this.label});

  /// Named so a screen reader announces what is coming, not just "loading".
  final String label;

  /// How long the cover holds before it starts to leave.
  static const Duration hold = Duration(milliseconds: 240);

  /// The fade out. Total cost of a tab switch is hold plus this.
  static const Duration fade = Duration(milliseconds: 180);

  @override
  State<PageVeil> createState() => _PageVeilState();
}

class _PageVeilState extends State<PageVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);

    // The arc is the app's own indicator rather than a Material spinner, and
    // an opaque surface underneath is what "blocks out the background" means.
    const arc = ArcProgress(value: 0.28, size: 58, stroke: 6);

    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ColoredBox(
          color: scheme.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reduceMotion)
                  arc
                else
                  RotationTransition(turns: _spin, child: arc),
                const SizedBox(height: 14),
                Text(
                  widget.label,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
