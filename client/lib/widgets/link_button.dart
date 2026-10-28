/// pill that opens a web page
///
/// 48 tall minimum for touch
/// label wraps, never truncates
library;

import 'package:flutter/material.dart';

import '../services/open_link.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'focus_ring.dart';
import 'app_icon.dart';
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
                          fontWeight: AppTheme.weight(Weights.medium),
                          fontVariations: Weights.medium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      AppIconKind.link.of(context),
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
