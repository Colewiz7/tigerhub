/// Caps and centres the content column, and splits it in two when there is
/// room.
///
/// A single 900px column centred on a 2400px monitor leaves most of the screen
/// empty. Past a threshold the same content runs as two columns, which uses the
/// width without making any single line longer.
library;

import 'package:flutter/material.dart';

class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child, this.maxWidth = 900});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// A list that becomes two columns on a wide window.
///
/// Items are dealt alternately rather than split down the middle, so the two
/// columns stay a similar height without needing to measure anything.
class ResponsiveList extends StatelessWidget {
  const ResponsiveList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 24),
    this.columnWidth = 560,
    this.twoColumnFrom = 1240,
  });

  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final EdgeInsets padding;

  /// Maximum width of one column. Lines never get longer than this.
  final double columnWidth;

  /// Below this the layout stays a single centred column.
  final double twoColumnFrom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoUp = constraints.maxWidth >= twoColumnFrom;
        if (!twoUp) {
          return ContentColumn(
            child: ListView.builder(
              padding: padding,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
          );
        }

        // Alternate rather than halve, so a long first item does not leave the
        // second column stubby.
        final left = [for (var i = 0; i < itemCount; i += 2) i];
        final right = [for (var i = 1; i < itemCount; i += 2) i];

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth * 2 + 16),
            child: SingleChildScrollView(
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Column(indices: left, builder: itemBuilder)),
                  const SizedBox(width: 16),
                  Expanded(child: _Column(indices: right, builder: itemBuilder)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.indices, required this.builder});

  final List<int> indices;
  final Widget Function(BuildContext, int) builder;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (final i in indices) builder(context, i)],
      );
}
