/// Dining settings: dietary filters and allergens to flag.
library;

import 'package:flutter/material.dart';

import '../../services/clipboard.dart';
import '../../services/preferences.dart';
import '../../theme/semantic.dart';
import '../../theme/tokens.dart';
import '../../widgets/menu_section.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/tab_bar.dart';

class DiningSection extends StatefulWidget {
  const DiningSection({super.key});

  @override
  State<DiningSection> createState() => _DiningSectionState();
}

class _DiningSectionState extends State<DiningSection> {
  final _prefs = Preferences.instance;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final semantic = Semantic.of(context);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: TabBarInset.pad(context, const EdgeInsets.fromLTRB(4, 6, 4, 24)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text('Groups', style: text.titleLarge?.copyWith(fontSize: 21)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Action(
              label: 'Reset groups',
              enabled: !_prefs.diningLayout.isEmpty,
              onTap: () {
                final before = _prefs.diningLayout;
                showFeedback(context, 'Groups reset', action: SnackBarAction(label: 'Undo', onPressed: () => _prefs.setDiningLayout(before)));
                _prefs.resetDiningGroups();
              },
            ),
            _Action(
              label: 'Unhide all',
              enabled: _prefs.hiddenDining.isNotEmpty,
              onTap: () {
                final before = _prefs.hiddenDining;
                showFeedback(
                  context,
                  'Places unhidden',
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () async {
                      for (final id in before) {
                        final place = int.tryParse(id);
                        if (place != null && !_prefs.isHidden(place)) await _prefs.toggleHidden(place);
                      }
                    },
                  ),
                );
                _prefs.unhideAllDining();
              },
            ),
          ],
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dietary', style: text.titleLarge?.copyWith(fontSize: 21)),
              const SizedBox(height: 4),
              Text(
                'Matching dishes sort to the top of a menu. Nothing is removed, '
                'because a hidden dish looks exactly like one that was never '
                'published.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in knownDietaryTags)
              _Toggle(
                label: tag,
                selected: _prefs.dietFilters.contains(tag),
                onTap: () => _prefs.toggleDiet(tag),
                selectedColor: semantic.open,
                selectedBackground: semantic.openContainer,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'These are the only two tags RIT publishes. Halal and kosher are not '
          'tagged at all, so this app will not claim a dish is either.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Allergens to flag',
                style: text.titleLarge?.copyWith(fontSize: 21),
              ),
              const SizedBox(height: 4),
              Text(
                'A dish containing one of these is marked on the menu. It is '
                'still shown, so you can see it and decide.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final allergen in knownAllergens)
              _Toggle(
                label: allergen,
                selected: _prefs.avoidAllergens.contains(allergen),
                onTap: () => _prefs.toggleAvoid(allergen),
                selectedColor: semantic.closed,
                selectedBackground: semantic.closedContainer,
              ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: Shapes.inner,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIconKind.warning.of(context),
                size: 18,
                color: semantic.closed,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'These tags come from RIT and are not verified by this app. '
                  'They describe ingredients, not preparation: shared fryers, '
                  'shared surfaces and shared equipment are not covered by any '
                  'of this. If an allergy is serious, ask the staff at the '
                  'counter every time.',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        elevation: 0,
        color: enabled ? scheme.primaryContainer : scheme.onSurface.withValues(alpha: 0.12),
        shape: Shapes.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: enabled ? scheme.onPrimaryContainer : scheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.selectedBackground,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color selectedBackground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        elevation: 0,
        color: selected ? selectedBackground : scheme.surfaceContainerHigh,
        shape: Shapes.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (selected ? AppIconKind.check : AppIconKind.add).of(context),
                  size: 15,
                  color: selected ? selectedColor : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? selectedColor : scheme.onSurface,
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
