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
  midnightBlue('midnight_blue', 'Midnight blue', DarkPalette.midnightBlue),
  midnightOrange('midnight_orange', 'Midnight orange', DarkPalette.midnightOrange);

  const AppScheme(this.id, this.label, this.palette);

  final String id;
  final String label;

  final DarkPalette palette;

  /// An old stored 'light' falls through to Espresso, as does anything unknown.
  static AppScheme parse(String? id) => values.firstWhere((s) => s.id == id, orElse: () => espresso);
}

class SchemeController extends ChangeNotifier {
  SchemeController({AppScheme initial = AppScheme.espresso}) : _choice = initial;

  static const _schemeKey = 'color_scheme';

  /// The app's own colour. RIT orange, seeded through Material's tonal system.
  static const Color fallbackSeed = Color(0xFFF76902);

  AppScheme _choice;
  AppScheme? _preview;
  bool _disposed = false;

  /// What the app shows now: a preview if one is up, else the stored choice.
  AppScheme get choice => _preview ?? _choice;

  /// The choice that survives a restart.
  AppScheme get storedChoice => _choice;

  bool get disposed => _disposed;

  ColorScheme get scheme => forChoice(choice);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Restore the stored choice. Espresso when nothing has been stored.
  Future<void> load() async {
    final stored = await ResponseCache.instance.readOrder(_schemeKey);
    _choice = AppScheme.parse(stored.isEmpty ? null : stored.first);
    notifyListeners();
  }

  /// Show a scheme without saving it, for setup to try looks on.
  void preview(AppScheme next) {
    if (choice == next) return;
    _preview = next;
    notifyListeners();
  }

  /// Drop a preview and go back to the stored choice.
  void clearPreview() {
    if (_preview == null) return;
    _preview = null;
    notifyListeners();
  }

  Future<void> select(AppScheme next) async {
    final shown = choice;
    _preview = null;
    if (_choice == next) {
      if (shown != next) notifyListeners();
      return;
    }
    _choice = next;
    notifyListeners();
    await ResponseCache.instance.writeOrder(_schemeKey, [next.id]);
  }

  /// The scheme for a choice.
  static ColorScheme forChoice(AppScheme choice) {
    return choice.palette.apply(ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: Brightness.dark));
  }

  /// The default scheme in either mode. Dark is Espresso. Light is the plain
  /// seed scheme, which no setting selects; widget tests use it for contrast.
  static ColorScheme builtIn(Brightness brightness) =>
      brightness == Brightness.dark ? forChoice(AppScheme.espresso) : ColorScheme.fromSeed(seedColor: fallbackSeed);
}
