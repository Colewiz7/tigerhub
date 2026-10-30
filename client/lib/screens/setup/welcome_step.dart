/// Step 1: the welcome. A mark, a title and what TigerHub does.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import 'setup_kit.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    return SetupPage(
      badge: ClipOval(
        child: Image.asset(
          'assets/images/tigerhub-mascot.png',
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
      title: 'Welcome to TigerHub',
      subtitle: 'Your campus in one place.',
      slivers: const [
        SliverList(
          delegate: SliverChildListDelegate.fixed([
            _Feature(glyph: AppIconKind.dining, title: "What's open to eat", line: 'Hours and menus across campus.'),
            _Feature(glyph: AppIconKind.events, title: "Events you'll care about", line: 'Filtered to your taste.'),
            _Feature(glyph: AppIconKind.campus, title: 'Campus at a glance', line: 'Shuttles, mail and hours on one screen.'),
          ]),
        ),
      ],
      primary: 'Continue',
      onPrimary: () => flow.next(context, SetupStep.welcome),
      secondary: 'Use defaults',
      onSecondary: flow.useDefaults,
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.glyph, required this.title, required this.line});

  final AppIconKind glyph;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$title. $line',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(dimension: 40, child: Center(child: AppIcon(glyph, size: 30, color: scheme.primary))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.bodyMedium?.copyWith(fontWeight: AppTheme.weight(Weights.bold), fontVariations: Weights.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(line, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
