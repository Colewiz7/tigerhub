/// Today's menu for one dining location, with allergen and dietary tags.
///
/// Two rules govern everything here, and both come from the data being about
/// what people can safely eat:
///
/// **Nothing is ever silently removed.** A dietary filter dims and demotes,
/// it does not delete. A missing dish is indistinguishable from a dish that was
/// never published, and quietly hiding food from someone looking for food is
/// the wrong failure.
///
/// **Tags are shown exactly as RIT publishes them.** They are not tidied,
/// merged, or inferred. "May Contain Traces of Milk" stays a weaker claim than
/// "Milk" rather than being folded into it.
///
/// Halal and kosher are deliberately absent: RIT does not tag either, and
/// guessing from a pork tag would be worse than saying nothing.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/preferences.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';

/// The dietary tags RIT actually uses. Not an aspirational list.
const List<String> knownDietaryTags = ['Vegan', 'Vegetarian'];

/// The allergens RIT actually tags, most common first.
const List<String> knownAllergens = [
  'Gluten',
  'Wheat',
  'Milk',
  'Egg',
  'Soy',
  'Coconut',
  'Treenut',
  'Sesame',
];

class MenuSection extends StatelessWidget {
  const MenuSection({super.key, required this.menu, required this.prefs});

  final MenuDay menu;
  final Preferences prefs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (menu.dishes.isEmpty) {
      return Text(
        'No menu published for today. Only some locations publish one, and a '
        'closed day has none.',
        style: text.bodySmall,
      );
    }

    // Matching dishes first, the rest still visible below.
    final wanted = <Dish>[];
    final rest = <Dish>[];
    for (final dish in menu.dishes) {
      (_matchesDiet(dish) ? wanted : rest).add(dish);
    }
    final filtering = prefs.dietFilters.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dish in wanted) _DishRow(dish: dish, prefs: prefs),
        if (filtering && rest.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${rest.length} more that do not match your filters',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        for (final dish in rest)
          _DishRow(dish: dish, prefs: prefs, demoted: filtering),
        const SizedBox(height: 14),
        _Caveat(),
      ],
    );
  }

  bool _matchesDiet(Dish dish) {
    if (prefs.dietFilters.isEmpty) return true;
    return prefs.dietFilters.every((tag) => switch (tag) {
          'Vegan' => dish.isVegan,
          'Vegetarian' => dish.isVegetarian,
          _ => dish.dietary.any((d) => d.toLowerCase() == tag.toLowerCase()),
        });
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.dish, required this.prefs, this.demoted = false});

  final Dish dish;
  final Preferences prefs;
  final bool demoted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final semantic = Semantic.of(context);

    final flagged = [
      for (final allergen in prefs.avoidAllergens)
        if (dish.mentions(allergen)) allergen,
    ];

    return Opacity(
      opacity: demoted ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: Shapes.inner,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(dish.name, style: text.titleMedium)),
                  if (flagged.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    // Flagged, not removed.
                    _Tag(
                      label: 'CONTAINS ${flagged.first.toUpperCase()}',
                      foreground: semantic.closed,
                      background: semantic.closedContainer,
                      icon: Icons.warning_amber_rounded,
                    ),
                  ],
                ],
              ),
              if (dish.category != null) ...[
                const SizedBox(height: 2),
                Text(dish.category!, style: text.bodySmall),
              ],
              if (dish.dietary.isNotEmpty || dish.allergens.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in dish.dietary)
                      _Tag(
                        label: tag,
                        foreground: semantic.open,
                        background: semantic.openContainer,
                        icon: Icons.eco_rounded,
                      ),
                    for (final allergen in dish.allergens)
                      _Tag(
                        label: allergen,
                        foreground: scheme.onSurfaceVariant,
                        background: scheme.surfaceContainerHighest,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 0,
        color: background,
        shape: Shapes.pill,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      );
}

/// The thing that has to be said out loud.
class _Caveat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Shapes.inner,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tags are exactly what RIT publishes and are not checked by this '
              'app. They say nothing about shared equipment or cross '
              'contamination. If an allergy matters, ask the staff at the '
              'counter.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
