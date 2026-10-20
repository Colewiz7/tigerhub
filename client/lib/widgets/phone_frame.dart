/// Dev only: shows the app in a phone sized box on desktop, enabled by TIGERHUB_PHONE.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PhoneMode {
  const PhoneMode({this.size = defaultSize, this.textScale});

  static const defaultSize = Size(390, 844);

  final Size size;
  final double? textScale;

  // unset, empty, 0 and false are off, anything else is on
  static PhoneMode? parse(Map<String, String> env, {bool release = kReleaseMode}) {
    if (release) return null;
    final raw = (env['TIGERHUB_PHONE'] ?? '').trim().toLowerCase();
    if (raw.isEmpty || raw == '0' || raw == 'false') return null;
    final scale = double.tryParse(env['TIGERHUB_TEXT_SCALE'] ?? '');
    return PhoneMode(
      size: _size(raw) ?? defaultSize,
      textScale: scale != null && scale > 0 && scale <= 4 ? scale : null,
    );
  }

  static PhoneMode? fromEnvironment() {
    try {
      return parse(Platform.environment);
    } catch (_) {
      return null;
    }
  }

  // a bad WxH falls back to the default size
  static Size? _size(String raw) {
    final match = RegExp(r'^(\d{3,4})x(\d{3,4})$').firstMatch(raw);
    if (match == null) return null;
    final width = double.parse(match[1]!);
    final height = double.parse(match[2]!);
    if (width < 200 || height < 200 || width > 2000 || height > 3000) return null;
    return Size(width, height);
  }
}

// for MaterialApp.builder, a no-op when the mode is off
TransitionBuilder phoneModeBuilder(PhoneMode? mode) => (context, child) => mode == null ? child! : PhoneFrame(mode: mode, child: child!);

class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.mode, required this.child});

  final PhoneMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        // a window smaller than the phone scales it down instead of overflowing
        child: FittedBox(
          child: SizedBox.fromSize(
            size: mode.size,
            child: MediaQuery(
              data: media.copyWith(
                size: mode.size,
                textScaler: mode.textScale == null ? null : TextScaler.linear(mode.textScale!),
              ),
              child: ClipRect(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
