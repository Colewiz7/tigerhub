/// The one-time sheet for someone who was using TigerHub before setup existed.
///
/// They already have settings, so the full flow would be a wall of questions
/// they answered long ago. The sheet says what is new and offers it. Either
/// button counts as an answer, and it never shows again.
library;

import 'package:flutter/material.dart';

import '../screens/setup/setup_kit.dart' show SetupBadge, SetupTextAction, setupButtonHeight;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
import 'focus_ring.dart';

/// True when they chose Personalize. Closing any other way is Not now.
Future<bool> showWhatsNewSheet(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  final chose = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    elevation: 0,
    backgroundColor: scheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Shapes.phoneCardRadius))),
    builder: (_) => const _WhatsNew(),
  );
  return chose ?? false;
}

class _WhatsNew extends StatelessWidget {
  const _WhatsNew();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SetupBadge(glyph: AppIconKind.celebration),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                "What's new in TigerHub",
                style: text.titleLarge?.copyWith(
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: AppTheme.weight(Weights.bold),
                  fontVariations: Weights.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make TigerHub yours in a minute.',
              style: text.bodyMedium?.copyWith(fontSize: 17, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            const _Line(glyph: AppIconKind.appearance, title: 'Pick a look', line: 'Choose a colour scheme.'),
            const _Line(glyph: AppIconKind.dining, title: 'Hide Dorm side', line: 'Keep a dining group off Dining and Today.'),
            const _Line(glyph: AppIconKind.todayTab, title: 'Your Today', line: 'Choose the cards and clubs you follow.'),
            const SizedBox(height: 8),
            FocusRing(
              radius: setupButtonHeight / 2,
              builder: (onFocusChange) => SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  onFocusChange: onFocusChange,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(setupButtonHeight),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Personalize'),
                ),
              ),
            ),
            Center(child: SetupTextAction(label: 'Not now', onTap: () => Navigator.of(context).pop(false))),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.glyph, required this.title, required this.line});

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
        padding: const EdgeInsets.only(bottom: 16),
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
