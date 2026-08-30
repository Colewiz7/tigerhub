/// Palette source.
///
/// **The built-in palette is the default.** This ships to people on many
/// different desktops, so the app cannot assume a wallpaper-derived scheme
/// exists, is readable, or is anything the user chose. A palette generated from
/// someone else's wallpaper is not a design, it is a guess.
///
/// Following the wallpaper is therefore opt in, off unless asked for, and Linux
/// only. It reads the Material scheme Caelestia generates, watches it, and
/// rebuilds live. It is genuinely nice on a machine that has one.
///
/// A build can pin the built-in palette outright with
/// `--dart-define=FORCE_SEED=true`, which also disables the opt in.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/cache.dart';
import 'scheme_source.dart';

/// Where the palette currently comes from. Surfaced in the UI so the answer is
/// never a guess.
enum SchemeOrigin {
  /// Generated from the wallpaper, read off disk.
  dynamicFile,

  /// The built-in seed, either as a fallback or because it was forced.
  seed,
}

class SchemeState {
  const SchemeState({
    required this.scheme,
    required this.origin,
    this.detail,
  });

  final ColorScheme scheme;
  final SchemeOrigin origin;

  /// Human readable source, for example the file path in use.
  final String? detail;

  bool get isDynamic => origin == SchemeOrigin.dynamicFile;
}

class SchemeController extends ChangeNotifier {
  SchemeController({bool? followWallpaper})
      : _forced = !(followWallpaper ?? false) {
    _state = _seedState('built-in palette');
  }

  static const _followKey = 'follow_wallpaper';

  /// Compile time override, so a broken scheme can be bypassed without a code
  /// change: --dart-define=FORCE_SEED=true
  static const bool forceSeedFromEnvironment =
      bool.fromEnvironment('FORCE_SEED');

  /// The app's own colour. RIT orange, seeded through Material's tonal system
  /// so both light and dark are generated from one hue and stay consistent
  /// wherever the app runs.
  static const Color fallbackSeed = Color(0xFFF76902);

  bool _forced;
  late SchemeState _state;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  SchemeState get state => _state;
  bool get forcedToSeed => _forced;

  /// Pin the built-in palette, or opt in to following the wallpaper.
  Future<void> setForceSeed(bool value) async {
    if (_forced == value) return;
    _forced = value;
    await ResponseCache.instance
        .writeOrder(_followKey, [value ? 'false' : 'true']);
    await load();
  }

  /// Restore the opt in, then load. Defaults to the built-in palette when
  /// nothing has been chosen.
  Future<void> restore() async {
    final stored = await ResponseCache.instance.readOrder(_followKey);
    _forced = stored.isEmpty || stored.first != 'true';
    await load();
  }

  Future<void> load() async {
    if (_forced || forceSeedFromEnvironment) {
      _emit(_seedState('forced to the built-in seed'));
      return;
    }

    final raw = await readScheme();
    final parsed = raw == null ? null : schemeFromJson(raw);
    if (parsed == null) {
      _emit(_seedState('no readable scheme file, using the seed'));
    } else {
      _emit(SchemeState(
        scheme: parsed,
        origin: SchemeOrigin.dynamicFile,
        detail: schemeSourceDescription,
      ));
    }

    // Follow the wallpaper from here on.
    await _subscription?.cancel();
    _subscription = watchScheme().listen((event) {
      if (_forced || forceSeedFromEnvironment) return;
      final next = schemeFromJson(event);
      if (next != null) {
        _emit(SchemeState(
          scheme: next,
          origin: SchemeOrigin.dynamicFile,
          detail: schemeSourceDescription,
        ));
      }
    }, onError: (_) {});
  }

  void _emit(SchemeState next) {
    _state = next;
    notifyListeners();
  }

  /// The built-in palette, in whichever mode is asked for.
  static ColorScheme builtIn(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: brightness);

  static SchemeState _seedState(String detail) => SchemeState(
        scheme: builtIn(Brightness.dark),
        origin: SchemeOrigin.seed,
        detail: detail,
      );

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Parse a hex string, with or without a leading hash, into a Color.
Color? parseHex(Object? value) {
  if (value is! String) return null;
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'ff$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Build a ColorScheme from the generated JSON.
///
/// Returns null when the payload is missing the roles that matter, so the
/// caller can fall back rather than render something half themed.
ColorScheme? schemeFromJson(Map<String, dynamic> json) {
  final colours = json['colours'] ?? json['colors'];
  if (colours is! Map) return null;
  final map = colours.map((k, v) => MapEntry(k.toString(), v));

  Color? role(String name) => parseHex(map[name]);

  final primary = role('primary');
  final surface = role('surface') ?? role('background');
  final onSurface = role('onSurface') ?? role('onBackground');
  if (primary == null || surface == null || onSurface == null) return null;

  final brightness =
      (json['mode']?.toString().toLowerCase() == 'light')
          ? Brightness.light
          : Brightness.dark;

  // Elevation is expressed only as surface tint, so the container levels are
  // derived by blending the tint over the surface at increasing strength. The
  // generated file does supply its own container roles, but they sit within a
  // few points of each other and the nesting becomes invisible.
  //
  // Calibrated against the real Caelestia settings panel, sampled pixel by
  // pixel. Its row fills sit only a little above the page (luminance about 8
  // against 3), and separation comes from the circular icon badges and the
  // gaps between rows, not from bright surfaces. Lifting these too far washes
  // the whole thing out, so the steps are moderate and the badges carry the
  // contrast instead.
  final tint = role('surfaceTint') ?? primary;
  final lift = role('primary') ?? primary;

  Color level(double tintAlpha, double liftAlpha) {
    final tinted = Color.alphaBlend(tint.withValues(alpha: tintAlpha), surface);
    // A touch of the primary on top keeps the steps warm and, more
    // importantly, keeps them far enough apart to actually see.
    return Color.alphaBlend(lift.withValues(alpha: liftAlpha), tinted);
  }

  return ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: role('onPrimary') ?? surface,
    primaryContainer: role('primaryContainer') ?? primary,
    onPrimaryContainer: role('onPrimaryContainer') ?? onSurface,
    secondary: role('secondary') ?? primary,
    onSecondary: role('onSecondary') ?? surface,
    secondaryContainer: role('secondaryContainer') ?? primary,
    onSecondaryContainer: role('onSecondaryContainer') ?? onSurface,
    tertiary: role('tertiary') ?? primary,
    onTertiary: role('onTertiary') ?? surface,
    tertiaryContainer: role('tertiaryContainer') ?? primary,
    onTertiaryContainer: role('onTertiaryContainer') ?? onSurface,
    error: role('error') ?? const Color(0xFFCF6679),
    onError: role('onError') ?? surface,
    errorContainer: role('errorContainer') ?? const Color(0xFF8C1D18),
    onErrorContainer: role('onErrorContainer') ?? onSurface,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: role('onSurfaceVariant') ?? onSurface,
    outline: role('outline') ?? onSurface,
    outlineVariant: role('outlineVariant') ?? onSurface,
    shadow: role('shadow') ?? const Color(0xFF000000),
    scrim: role('scrim') ?? const Color(0xFF000000),
    inverseSurface: role('inverseSurface') ?? onSurface,
    onInverseSurface: role('inverseOnSurface') ?? surface,
    inversePrimary: role('inversePrimary') ?? primary,
    surfaceTint: tint,
    surfaceContainerLowest: surface,
    surfaceContainerLow: level(0.28, 0.010),
    surfaceContainer: level(0.38, 0.018),
    surfaceContainerHigh: level(0.50, 0.030),
    surfaceContainerHighest: level(0.65, 0.055),
  );
}
