/// A pill that opens a web page outside the app.
///
/// 48 tall at least, so the whole pill is the touch target. The label wraps
/// rather than truncating, so large text grows the pill instead of cutting
/// the words. Keyboard focus draws the shared 2px ring.
library;

import 'package:flutter/material.dart';

import '../services/open_link.dart';
import '../theme/tokens.dart';
import 'more_row.dart';
import 'touch_target.dart';

class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.label, required this.url});

  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      link: true,
      label: label,
      hint: 'Opens externally',
      excludeSemantics: true,
      onTap: () => openOrCopy(context, url, label: label),
      child: FocusRing(
        radius: TouchTarget.size / 2,
        builder: (onFocusChange) => Material(
          elevation: 0,
          color: scheme.surfaceContainerHigh,
          shape: Shapes.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openOrCopy(context, url, label: label),
            onFocusChange: onFocusChange,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: TouchTarget.size),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontVariations: Weights.medium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
