/// A collapsed "Hidden (n)" header that opens to the rows the reader hid.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';

class HiddenGroup extends StatefulWidget {
  const HiddenGroup({super.key, required this.count, required this.children});

  final int count;
  final List<Widget> children;

  @override
  State<HiddenGroup> createState() => _HiddenGroupState();
}

class _HiddenGroupState extends State<HiddenGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = 'Hidden (${widget.count})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: Shapes.inner,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    RotatedBox(
                      quarterTurns: _open ? 2 : 0,
                      child: AppIcon(AppIconKind.expand, size: 22, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}
