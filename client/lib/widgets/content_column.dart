/// Caps and centres the content column.
///
/// Rows ran the full window width, which is 2400px plus on a desktop monitor
/// and unreadable. Line length is capped so the eye does not have to travel
/// the whole screen between a name and its status.
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
