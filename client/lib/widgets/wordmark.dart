import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config.dart';

/// The masthead wordmark.
///
/// Codex's art, not type set here. "Tiger" carries the orange with three
/// tapered stripes cut through the letterforms, and "Hub" is the quiet half,
/// which is the reverse of what this used to do.
///
/// The wide mark needs 230 logical pixels and the compact one 184, per
/// `assets/generated/SPEC.md`, so the masthead picks by the width it actually
/// gets rather than by window size: it sits in a Row with the settings and
/// palette buttons, so the window is not the space available.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  static const double _wideFrom = 230;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideFrom;
          return SvgPicture.asset(
            wide
                ? 'assets/generated/wordmark/tigerhub-wide.svg'
                : 'assets/generated/wordmark/tigerhub-compact.svg',
            height: wide ? 40 : 34,
            // The art names the app, so it is the label rather than being
            // decorative. Without this a screen reader announces nothing here.
            semanticsLabel: AppConfig.appName,
          );
        },
      );
}

