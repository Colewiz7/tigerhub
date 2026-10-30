/// A small stand-in for the top of Today, drawn in whatever theme is around it.
///
/// Setup uses it twice: side by side in each colour scheme to pick a look, and
/// once above the card toggles so each switch visibly moves something. It is
/// drawn, not the real screen, so it needs no data and does not move. It is
/// always laid out at phone size and scaled down.
library;

import 'package:flutter/material.dart';

import '../../home_screen.dart' show moduleIcons;
import '../../services/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';

/// The cards the shipped Today starts with.
const List<({ModuleType type, CardSize size})> defaultMiniCards = [
  (type: ModuleType.diningStatus, size: CardSize.standard),
  (type: ModuleType.generalEvents, size: CardSize.standard),
  (type: ModuleType.visitingChefs, size: CardSize.standard),
  (type: ModuleType.mailingAddress, size: CardSize.standard),
];

/// Lays [child] out at [width] by [height] and scales it to fit [displayWidth].
/// Nothing in it takes taps or reads out.
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.displayWidth,
    required this.displayHeight,
    required this.child,
    this.width = 390,
    this.height = 844,
  });

  final double displayWidth;
  final double displayHeight;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: height,
              // a fixed text size, so the picture is the same at every setting
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MiniToday extends StatelessWidget {
  const MiniToday({super.key, this.cards = defaultMiniCards, this.tabBar = true});

  final List<({ModuleType type, CardSize size})> cards;
  final bool tabBar;

  static String? _pill(ModuleType type) => switch (type) {
    ModuleType.diningStatus => '4 open',
    ModuleType.generalEvents => '3 today',
    ModuleType.visitingChefs => '1 today',
    ModuleType.clubEvents => '2 soon',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
            // more cards than fit are cut off, as the real screen scrolls
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
              children: [
                Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/images/tigerhub-mascot.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const Spacer(),
                    SizedBox.square(
                      dimension: 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surfaceContainerHigh),
                        child: Icon(AppIconKind.settings.of(context), size: 22, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final card in cards) _Tile(type: card.type, size: card.size),
              ],
              ),
            ),
          ),
          if (tabBar)
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: DecoratedBox(
                decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(32)),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 5; i++)
                        SizedBox.square(
                          dimension: 28,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == 0 ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.type, required this.size});

  final ModuleType type;
  final CardSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pill = MiniToday._pill(type);
    final bar = scheme.onSurfaceVariant.withValues(alpha: 0.35);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: Shapes.phoneCard),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withValues(alpha: 0.3)),
                      child: Icon(moduleIcons[type]?.of(context), size: 18, color: scheme.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      moduleLabels[type] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                  if (pill != null)
                    DecoratedBox(
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Text(
                          pill,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onPrimary,
                            fontSize: 14,
                            fontWeight: AppTheme.weight(Weights.medium),
                            fontVariations: Weights.medium,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (size != CardSize.compact) ...[
                const SizedBox(height: 14),
                FractionallySizedBox(
                  widthFactor: 0.78,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(5)),
                    child: const SizedBox(height: 10),
                  ),
                ),
                const SizedBox(height: 10),
                FractionallySizedBox(
                  widthFactor: 0.52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(5)),
                    child: const SizedBox(height: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
