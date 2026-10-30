/// Step 6: your Today. A small picture of the top of Today, and a switch for
/// each card that can sit there.
library;

import 'package:flutter/material.dart';

import '../../home_screen.dart' show moduleIcons;
import '../../services/setup_draft.dart';
import '../../widgets/app_icon.dart';
import 'mini_today.dart';
import 'setup_kit.dart';

class TodayStep extends StatelessWidget {
  const TodayStep({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final plan = TodayPlan.of(base: flow.dashboard, draft: flow.draft);
        final shown = [
          for (final card in plan.cards)
            if (!card.hidden) (type: card.type, size: card.size),
        ];
        final chosen = flow.rerun || flow.draft.hasToday;
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.todayTab),
          title: 'Your Today',
          subtitle: 'Choose the cards at the top of Today.',
          leading: flow.leadingFor(context, SetupStep.today),
          trailing: flow.trailingFor(context),
          afterHeader: Center(
            child: DecoratedBox(
              key: const ValueKey('today-preview'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: MiniScreen(
                  displayWidth: 200,
                  displayHeight: 220,
                  height: 429,
                  child: MiniToday(cards: shown, tabBar: false),
                ),
              ),
            ),
          ),
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                SetupGroup(
                  children: [
                    for (final entry in plan.rows)
                      _CardRow(
                        label: entry.row.label,
                        glyph: moduleIcons[entry.row.type] ?? AppIconKind.widgets,
                        on: entry.on,
                        onChanged: (on) {
                          setupSelect();
                          final club = entry.row.club;
                          if (club != null) {
                            on ? flow.draft.followClub(club, entry.row.label) : flow.draft.unfollowClub(club);
                          } else {
                            flow.draft.setCard(entry.row.type, on);
                          }
                        },
                      ),
                  ],
                ),
              ]),
            ),
          ],
          primary: setupPrimaryLabel(chosen: chosen),
          // nothing chosen, so the flow ends here with what it has
          onPrimary: () => chosen ? flow.next(context, SetupStep.today) : flow.finish(context),
        );
      },
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.label, required this.glyph, required this.on, required this.onChanged});

  final String label;
  final AppIconKind glyph;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SetupRow(
      title: label,
      selected: on,
      semanticsLabel: '$label, ${on ? 'on' : 'off'}',
      leading: SizedBox.square(
        dimension: 30,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withValues(alpha: 0.3)),
          child: Center(child: AppIcon(glyph, size: 17, color: scheme.primary)),
        ),
      ),
      onTap: () => onChanged(!on),
      trailing: ExcludeSemantics(child: Switch(value: on, onChanged: onChanged)),
    );
  }
}
