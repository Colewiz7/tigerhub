/// The tab bar.
///
/// Icon stacked above label, accent underline on the active tab, muted when
/// inactive. No pill backgrounds and no boxes: the underline is the only
/// indicator, which keeps it quiet the way an editor's tab strip is.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class TabSpec {
  const TabSpec({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelect,
  });

  final List<TabSpec> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.surfaceContainerLowest,
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _Tab(
                spec: tabs[i],
                active: i == index,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.spec, required this.active, required this.onTap});

  final TabSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 11),
          Icon(spec.icon, size: 29, color: color),
          const SizedBox(height: 6),
          Text(
            spec.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontVariations: active ? Weights.semibold : Weights.regular,
                ),
          ),
          const SizedBox(height: 8),
          // The underline is the whole indicator.
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 3,
            width: active ? 34 : 0,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
