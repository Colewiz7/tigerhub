/// A long grouped list with a sidebar that jumps to a group.
///
/// The Dining and Events tabs are one long scroll of groups. On a wide window
/// there is room for a rail beside them, so a group is one click away instead
/// of a scroll and a hunt. On a narrow window the rail would cost more than it
/// gives, so it is dropped and the list behaves as before.
///
/// The rail also marks which group you are currently in, so it doubles as a
/// position indicator rather than only a control.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class JumpGroup {
  const JumpGroup({
    required this.label,
    required this.icon,
    required this.count,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final int count;
  final WidgetBuilder builder;
}

class JumpList extends StatefulWidget {
  const JumpList({
    super.key,
    required this.groups,
    this.footer,
    this.railFrom = 1100,
    this.railWidth = 240,
    this.contentMaxWidth = 900,
  });

  final List<JumpGroup> groups;
  final Widget? footer;

  /// Below this the rail is not worth the width it costs.
  final double railFrom;
  final double railWidth;
  final double contentMaxWidth;

  @override
  State<JumpList> createState() => _JumpListState();
}

class _JumpListState extends State<JumpList> {
  final _controller = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _active = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  Iterable<int> get _builtIndices => _keys.entries
      .where((e) => e.value.currentContext != null)
      .map((e) => e.key);

  /// A far group has not been built yet, so its key has no context and there is
  /// nothing for ensureVisible to scroll to. Walk the viewport toward it a
  /// screen at a time, letting each frame build more of the list, then hand off
  /// to ensureVisible for the last, animated hop.
  Future<void> _jumpTo(int index) async {
    setState(() => _active = index);
    for (var step = 0; step < 40; step++) {
      final target = _keyFor(index).currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.02,
        );
        return;
      }
      if (!_controller.hasClients) return;
      final pos = _controller.position;
      final forward = _builtIndices.every((i) => i < index);
      final next = (pos.pixels + (forward ? 1 : -1) * pos.viewportDimension)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (next == pos.pixels) return;
      _controller.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  /// Which group the viewport is currently showing, so the rail tracks the
  /// scroll rather than only responding to clicks.
  void _syncActive() {
    var best = _active;
    var bestTop = double.infinity;
    for (final entry in _keys.entries) {
      final context = entry.value.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= 160 && top.abs() < bestTop) {
        bestTop = top.abs();
        best = entry.key;
      }
    }
    if (best != _active) setState(() => _active = best);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail =
            constraints.maxWidth >= widget.railFrom && widget.groups.length > 1;

        final list = NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _syncActive();
            return false;
          },
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: widget.groups.length + 1,
            itemBuilder: (context, index) {
              if (index == widget.groups.length) {
                return widget.footer ?? const SizedBox.shrink();
              }
              return Padding(
                key: _keyFor(index),
                padding: const EdgeInsets.only(bottom: 14),
                child: widget.groups[index].builder(context),
              );
            },
          ),
        );

        final bounded = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.contentMaxWidth),
            child: list,
          ),
        );

        if (!showRail) return bounded;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: widget.railWidth,
              child: _Rail(
                groups: widget.groups,
                active: _active,
                onSelect: _jumpTo,
              ),
            ),
            Expanded(child: bounded),
          ],
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.groups,
    required this.active,
    required this.onSelect,
  });

  final List<JumpGroup> groups;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 24),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final on = index == active;
        final media = MediaQuery.maybeOf(context);
        final reduceMotion =
            (media?.disableAnimations ?? false) ||
            (media?.accessibleNavigation ?? false);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: on ? 1 : 0),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              elevation: 0,
              color: scheme.primary.withValues(alpha: 0.20 * value),
              borderRadius: Shapes.small,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelect(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        groups[index].icon,
                        size: 17,
                        color: Color.lerp(
                          scheme.onSurfaceVariant,
                          scheme.primary,
                          value,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          groups[index].label,
                          style: text.bodySmall?.copyWith(
                            color: Color.lerp(
                              scheme.onSurface,
                              scheme.primary,
                              value,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right aligned in a fixed box so the counts line up with
                      // each other instead of chasing the ragged label ends.
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${groups[index].count}',
                          textAlign: TextAlign.right,
                          style: text.bodySmall?.copyWith(
                            color: Color.lerp(
                              scheme.onSurfaceVariant,
                              scheme.primary,
                              value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
