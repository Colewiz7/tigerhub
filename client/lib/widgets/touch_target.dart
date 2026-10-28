/// A 48pt hit region around a smaller visual.
///
/// The spec: visual size may be smaller, the hit area never is. Flutter only
/// hit-tests inside a parent's layout box, so the region is a real 48 tall box
/// with the visual centered in it. Taps anywhere in the box land on [onTap];
/// the visual keeps its own state layer and semantics.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A 48pt hit square around a small control whose layout box must stay
/// small, where a [TouchTarget] box would move what is around it.
///
/// Flutter drops a tap outside a parent's box before it reaches the child,
/// so the square is checked by the nearest [HitSlopRegion] above, which must
/// be big enough to hold it. Where two squares overlap the nearer control
/// takes the tap.
class HitSlopTarget extends SingleChildRenderObjectWidget {
  const HitSlopTarget({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderHitSlopTarget();
}

class RenderHitSlopTarget extends RenderProxyBox {
  _RenderHitSlopRegion? _region;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var node = parent;
    while (node != null && node is! _RenderHitSlopRegion) {
      node = node.parent;
    }
    _region = node as _RenderHitSlopRegion?;
    _region?._targets.add(this);
  }

  @override
  void detach() {
    _region?._targets.remove(this);
    _region = null;
    super.detach();
  }
}

/// Routes taps that land in a [HitSlopTarget]'s square to that target.
class HitSlopRegion extends SingleChildRenderObjectWidget {
  const HitSlopRegion({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitSlopRegion();
}

class _RenderHitSlopRegion extends RenderProxyBox {
  final Set<RenderHitSlopTarget> _targets = {};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    RenderHitSlopTarget? best;
    Matrix4? bestTransform;
    var bestDistance = double.infinity;
    for (final target in _targets) {
      if (!target.attached || !target.hasSize) continue;
      final transform = target.getTransformTo(this);
      final rect = MatrixUtils.transformRect(transform, Offset.zero & target.size);
      final square = Rect.fromCenter(
        center: rect.center,
        width: rect.width < TouchTarget.size ? TouchTarget.size : rect.width,
        height: rect.height < TouchTarget.size ? TouchTarget.size : rect.height,
      );
      if (!square.contains(position)) continue;
      final distance = (position - rect.center).distance;
      if (distance < bestDistance) {
        best = target;
        bestTransform = transform;
        bestDistance = distance;
      }
    }
    final target = best;
    if (target != null) {
      final hit = result.addWithPaintTransform(
        transform: bestTransform,
        position: position,
        // pulled inside, so the control takes it as its own
        hitTest: (result, local) => target.hitTest(
          result,
          position: Offset(
            local.dx.clamp(0, target.size.width - 0.01),
            local.dy.clamp(0, target.size.height - 0.01),
          ),
        ),
      );
      if (hit) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return super.hitTest(result, position: position);
  }
}

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
