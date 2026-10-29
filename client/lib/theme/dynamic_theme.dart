/// The colour scheme in force.
///
/// The scheme is a choice stored in settings. It never follows the OS or the
/// wallpaper: nothing in this app reads the system brightness or a generated
/// scheme file. Espresso, a dark palette, is the default.
library;

import 'package:flutter/material.dart';

import '../services/cache.dart';
import 'dark_palette.dart';

/// The schemes a user can pick in Settings.
enum AppScheme {
  espresso('espresso', 'Espresso', DarkPalette.espresso),
  mocha('mocha', 'Mocha', DarkPalette.mocha),
  slate('slate', 'Slate', DarkPalette.slate),
  light('light', 'Light', null);

  const AppScheme(this.id, this.label, this.palette);

  final String id;
  final String label;

  /// Null for the light scheme, which is the plain seed scheme.
  final DarkPalette? palette;

  Brightness get brightness => palette == null ? Brightness.light : Brightness.dark;

  static AppScheme parse(String? id) => values.firstWhere((s) => s.id == id, orElse: () => espresso);
}

class SchemeController extends ChangeNotifier {
  SchemeController({AppScheme initial = AppScheme.espresso}) : _choice = initial;

  static const _schemeKey = 'color_scheme';

  /// The app's own colour. RIT orange, seeded through Material's tonal system.
  static const Color fallbackSeed = Color(0xFFF76902);

  AppScheme _choice;

  AppScheme get choice => _choice;
  ColorScheme get scheme => forChoice(_choice);

  /// Restore the stored choice. Espresso when nothing has been stored.
  Future<void> load() async {
    final stored = await ResponseCache.instance.readOrder(_schemeKey);
    _choice = AppScheme.parse(stored.isEmpty ? null : stored.first);
    notifyListeners();
  }

  Future<void> select(AppScheme next) async {
    if (_choice == next) return;
    _choice = next;
    notifyListeners();
    await ResponseCache.instance.writeOrder(_schemeKey, [next.id]);
  }

  /// The scheme for a choice.
  static ColorScheme forChoice(AppScheme choice) {
    final seeded = ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: choice.brightness);
    return choice.palette?.apply(seeded) ?? seeded;
  }

  /// The default scheme in either mode. Dark is Espresso, light is the seed
  /// scheme as is.
  static ColorScheme builtIn(Brightness brightness) =>
      forChoice(brightness == Brightness.dark ? AppScheme.espresso : AppScheme.light);
}
