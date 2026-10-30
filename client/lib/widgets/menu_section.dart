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
import '../models/diet_class.dart';
import '../motion/reduce_motion.dart';
import '../services/preferences.dart';
import '../theme/diet_palette.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

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

    final filtering = prefs.dietFilters.isNotEmpty;
    final restCount = menu.dishes.where((d) => !_matchesDiet(d)).length;

    // Station order is the order the feed first names them, Other last.
    final stations = <String, List<Dish>>{};
    for (final dish in menu.dishes) {
      stations.putIfAbsent(stationOf(dish), () => []).add(dish);
    }
    final names = [
      for (final name in stations.keys)
        if (name != otherStation && isSpecialStation(name)) name,
      for (final name in stations.keys)
        if (name != otherStation && !isSpecialStation(name)) name,
      if (stations.containsKey(otherStation)) otherStation,
    ];
    // the station that led before specials moved up stays open
    final firstPlain = names.indexWhere((n) => n != otherStation && !isSpecialStation(n));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filtering && restCount > 0) ...[
          Text(
            '$restCount more that do not match your filters',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < names.length; i++)
          _StationSection(
            key: ValueKey('station-section-${names[i]}'),
            station: names[i],
            // A filter opens every section with a match, so folding never
            // hides a dish the person asked for.
            initiallyOpen:
                i == 0 ||
                isSpecialStation(names[i]) ||
                i == (firstPlain < 0 ? 0 : firstPlain) ||
                (filtering && stations[names[i]]!.any(_matchesDiet)),
            // Matching dishes first, the rest still visible below.
            dishes: [
              ...stations[names[i]]!.where(_matchesDiet),
              ...stations[names[i]]!.where((d) => !_matchesDiet(d)),
            ],
            prefs: prefs,
            demoteUnmatched: filtering,
            matches: _matchesDiet,
          ),
        const SizedBox(height: 14),
        _Caveat(),
      ],
    );
  }

  /// Chef specials and any station like it, which lead the menu.
  static bool isSpecialStation(String station) => station.toLowerCase().contains('special');

  /// The station a dish is served from, which is its published category.
  static String stationOf(Dish dish) {
    final category = dish.category?.trim();
    return category == null || category.isEmpty ? otherStation : category;
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

/// Where a dish goes when the feed names no category.
const String otherStation = 'Other';

class _StationSection extends StatefulWidget {
  const _StationSection({
    super.key,
    required this.station,
    required this.initiallyOpen,
    required this.dishes,
    required this.prefs,
    required this.demoteUnmatched,
    required this.matches,
  });

  final String station;
  final bool initiallyOpen;
  final List<Dish> dishes;
  final Preferences prefs;
  final bool demoteUnmatched;
  final bool Function(Dish) matches;

  @override
  State<_StationSection> createState() => _StationSectionState();
}

class _StationSectionState extends State<_StationSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = widget.dishes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: '${widget.station}, $count ${count == 1 ? 'item' : 'items'}',
          excludeSemantics: true,
          onTap: () => setState(() => _open = !_open),
          child: InkWell(
            key: ValueKey('station-${widget.station}'),
            borderRadius: Shapes.inner,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(widget.station, style: text.titleSmall)),
                    const SizedBox(width: 8),
                    Text('$count', style: text.labelSmall),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: reduceMotion(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      child: Icon(
                        AppIconKind.expand.of(context),
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          for (final dish in widget.dishes)
            _DishRow(
              dish: dish,
              prefs: widget.prefs,
              showCategory: false,
              demoted: widget.demoteUnmatched && !widget.matches(dish),
            ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.dish,
    required this.prefs,
    this.demoted = false,
    this.showCategory = true,
  });

  final Dish dish;
  final Preferences prefs;
  final bool demoted;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final semantic = Semantic.of(context);

    final flagged = [
      for (final allergen in prefs.avoidAllergens)
        if (dish.mentions(allergen)) allergen,
    ];

    final mark = classifyDish(dish);
    final tint = DietPalette.of(context)[mark.kind];

    // A dish that misses the filter keeps full contrast text. It recedes by
    // losing its tint, dropping a size and saying so, never by fading.
    final fill = demoted ? scheme.surfaceContainerLow : tint.container;
    final ink = demoted ? scheme.onSurfaceVariant : tint.onContainer;
    final colors = (container: fill, onContainer: ink, accent: tint.accent, onAccent: tint.onAccent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
          key: ValueKey('dish-${dish.name}'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.container,
            borderRadius: Shapes.inner,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      dish.name,
                      style: (demoted ? text.titleSmall : text.titleMedium)
                          ?.copyWith(color: colors.onContainer),
                    ),
                  ),
                  if (flagged.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    // Flagged, not removed.
                    _Tag(
                      label: 'Contains ${flagged.first.toLowerCase()}',
                      foreground: semantic.closed,
                      background: semantic.closedContainer,
                      icon: AppIconKind.warning,
                    ),
                  ],
                ],
              ),
              if (showCategory && dish.category != null) ...[
                const SizedBox(height: 2),
                Text(
                  dish.category!,
                  style: text.bodySmall?.copyWith(color: colors.onContainer),
                ),
              ],
              if (dish.dietary.isNotEmpty ||
                  dish.allergens.isNotEmpty ||
                  mark.tag != null) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // The class in words, so the tint is never the only signal.
                    if (mark.tag != null)
                      _Tag(
                        key: ValueKey('diet-label-${mark.tag}'),
                        label: mark.tag!,
                        foreground: colors.onAccent,
                        background: colors.accent,
                        icon: dietIcon(mark.kind),
                      ),
                    for (final tag in dish.dietary)
                      if (tag.trim() != mark.tag)
                        _Tag(
                          label: tag.trim(),
                          foreground: scheme.onSurfaceVariant,
                          background: scheme.surfaceContainerHighest,
                        ),
                    for (final allergen in dish.allergens)
                      if (allergen.trim() != mark.tag)
                        _Tag(
                          label: allergen.trim(),
                          foreground: scheme.onSurfaceVariant,
                          background: scheme.surfaceContainerHighest,
                        ),
                  ],
                ),
              ],
              if (demoted) ...[
                const SizedBox(height: 9),
                _Tag(
                  label: 'Doesn’t match',
                  foreground: scheme.onSurfaceVariant,
                  background: scheme.surfaceContainerHighest,
                ),
              ],
            ],
          ),
        ),
    );
  }
}

/// The icon that goes with a class label.
AppIconKind dietIcon(DietClass kind) => switch (kind) {
  DietClass.vegan || DietClass.vegetarian => AppIconKind.plant,
  DietClass.fish => AppIconKind.fish,
  DietClass.beef || DietClass.pork || DietClass.chicken => AppIconKind.meat,
  DietClass.other => AppIconKind.cutlery,
};

/// What each tint means. Sits above the menu, outside any section, so it reads
/// once.
class DietLegend extends StatelessWidget {
  const DietLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = DietPalette.of(context);
    return Wrap(
      key: const ValueKey('diet-legend'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final kind in DietClass.values)
          _Tag(
            label: kind.label,
            foreground: palette[kind].onContainer,
            background: palette[kind].container,
            icon: dietIcon(kind),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final AppIconKind? icon;

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
                Icon(icon!.of(context), size: 12, color: foreground),
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
          Icon(AppIconKind.info.of(context), size: 16, color: scheme.onSurfaceVariant),
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
