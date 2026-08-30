/// Partial-sweep circular progress.
///
/// CircularProgressIndicator only draws a full 360 track, so this is a small
/// painter instead: a gap at the bottom, a visibly darker track ring behind,
/// a thick stroke with round caps. Written once and reused.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class ArcProgress extends StatelessWidget {
  const ArcProgress({
    super.key,
    required this.value,
    this.size = 92,
    this.stroke = 9,
    this.sweepDegrees = 260,
    this.child,
  });

  /// 0 to 1. Values above 1 are clamped by the painter.
  final double value;
  final double size;
  final double stroke;

  /// How much of the circle the track covers. Deliberately under 360.
  final double sweepDegrees;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final target = value.clamp(0.0, 1.0);

    Widget paint(double animatedValue) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ArcPainter(
          value: animatedValue,
          stroke: stroke,
          sweep: sweepDegrees * math.pi / 180,
          track: scheme.surfaceContainerHighest,
          fill: scheme.primary,
        ),
        child: Center(child: child),
      ),
    );

    if (reduceMotion) return paint(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) => paint(animatedValue),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.value,
    required this.stroke,
    required this.sweep,
    required this.track,
    required this.fill,
  });

  final double value;
  final double stroke;
  final double sweep;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);
    // Centre the gap at the bottom of the circle.
    final start = math.pi / 2 + (2 * math.pi - sweep) / 2;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawArc(inset, start, sweep, false, base);

    if (value <= 0) return;
    canvas.drawArc(inset, start, sweep * value, false, base..color = fill);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}
