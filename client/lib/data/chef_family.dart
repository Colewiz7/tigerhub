/// Cuisine family for a visiting chef, which picks the row icon.
library;

import '../models/api_models.dart';
import '../widgets/app_icon.dart';

enum ChefFamily {
  sushi('Sushi and rolls', AppIconKind.fish, r'sushi|sashimi|nigiri|maki|\bpoke\b'),
  indianMiddleEastern('Indian and Middle Eastern', AppIconKind.meat, r'indian|pakistani|tandoor|curry|kebab|kabob|halal|falafel|shawarma|gyro|middle eastern|persian|lebanese|turkish|afghan|bangladesh|nepal'),
  mexicanLatin('Mexican and Latin', AppIconKind.tapas, r'mexican|latin|taco|burrito|tex-mex|arepa|empanada|peruvian|colombian|venezuelan|salvadoran'),
  pizzaItalian('Pizza and Italian', AppIconKind.pizza, r'pizza|italian|pasta|calzone'),
  bbqGrill('BBQ and grill', AppIconKind.grill, r'bbq|barbecue|barbeque|grill|smokehouse|\bribs?\b|\bwings?\b'),
  asianNoodles('Asian noodles', AppIconKind.ramen, r'asian|korean|chinese|sichuan|szechuan|cantonese|hunan|japanese|thai|vietnamese|ramen|noodle|\bpho\b|lo mein|dumpling|\bwok\b'),
  caribbeanRice('Caribbean and rice dishes', AppIconKind.riceBowl, r'caribbean|dominican|jamaican|haitian|cuban|puerto|creole|jerk|plantain|\brice\b'),
  desserts('Desserts', AppIconKind.cake, r'dessert|\bcakes?\b|pastry|pastries|\bbak(e|ed|ery)\b|sweets?\b|ice cream|cookie|donut|doughnut|crepe'),
  breakfast('Breakfast', AppIconKind.breakfast, r'breakfast|brunch|pancake|waffle|\beggs?\b'),
  saladVegan('Salad and vegan', AppIconKind.plant, r'salad|vegan|vegetarian|plant.based|vegetable'),
  burgers('Burgers', AppIconKind.deli, r'burger|slider|hot dog'),
  sandwichesDeli('Sandwiches and deli', AppIconKind.bento, r'sandwich|\bdeli\b|\bsubs?\b|panini|\bwraps?\b'),
  unknown('Unknown', AppIconKind.menu, r'$^');

  const ChefFamily(this.label, this.icon, this._pattern);

  final String label;
  final AppIconKind icon;
  final String _pattern;

  // first match wins, so the specific families sit above the broad ones
  static ChefFamily of(String text) {
    for (final family in values) {
      if (RegExp(family._pattern, caseSensitive: false).hasMatch(text)) return family;
    }
    return unknown;
  }
}

ChefFamily chefFamily(MenuItem chef) => ChefFamily.of('${chef.name} ${chef.cuisine ?? ''}');

AppIconKind iconForChef(MenuItem chef) => chefFamily(chef).icon;
