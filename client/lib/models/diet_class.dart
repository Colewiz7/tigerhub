/// Which diet or protein a dish falls under, from the tags RIT publishes.
///
/// The feed tags Vegetarian, Vegan, Pork and Beef (verified 2026-08-30 over 771
/// recipes). It has no chicken or fish tag and no ingredient list, so those two
/// classes only appear if a tag ever says so. A dish name is never read:
/// guessing a protein from "Grilled salmon" is the same inference this app
/// refuses for halal and kosher.
library;

import 'api_models.dart';

enum DietClass {
  vegan('Vegan'),
  vegetarian('Vegetarian'),
  beef('Beef'),
  pork('Pork'),
  chicken('Chicken'),
  fish('Fish'),
  other('Other');

  const DietClass(this.label);

  final String label;
}

/// Tags that name a protein, matched whole and ignoring case. "May Contain
/// Traces of Fish" is an allergen warning, not the dish, so it does not match.
const _proteinTags = <DietClass, Set<String>>{
  DietClass.beef: {'beef'},
  DietClass.pork: {'pork'},
  DietClass.chicken: {'chicken', 'poultry'},
  DietClass.fish: {'fish'},
};

/// The class and the published tag that decided it, trimmed. Tags match whole,
/// so "Non-Vegetarian" is not vegetarian. Meat wins over vegetarian when a dish
/// carries both, since that is the claim to avoid getting wrong.
({DietClass kind, String? tag}) classifyDish(Dish dish) {
  final tags = [
    for (final tag in [...dish.dietary, ...dish.allergens]) tag.trim(),
  ];
  final dietary = [for (final tag in dish.dietary) tag.trim()];

  for (final entry in _proteinTags.entries) {
    for (final tag in tags) {
      if (entry.value.contains(tag.toLowerCase())) {
        return (kind: entry.key, tag: tag);
      }
    }
  }
  for (final tag in dietary) {
    if (tag.toLowerCase() == 'vegan') return (kind: DietClass.vegan, tag: tag);
  }
  for (final tag in dietary) {
    if (tag.toLowerCase() == 'vegetarian') {
      return (kind: DietClass.vegetarian, tag: tag);
    }
  }
  return (kind: DietClass.other, tag: null);
}

DietClass dietClassOf(Dish dish) => classifyDish(dish).kind;
