/// Step 7: all set. What was picked, and the way into the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/api_models.dart';
import '../../services/filter_profiles.dart';
import '../../services/setup_draft.dart';
import '../../widgets/app_icon.dart';
import 'setup_kit.dart';

class DoneStep extends StatelessWidget {
  const DoneStep({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final picks = _picks(flow);
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.check, size: 96),
          title: "You're all set",
          subtitle: 'Change any of this in Settings.',
          leading: flow.leadingFor(context, SetupStep.done),
          trailing: null,
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                SetupGroup(
                  children: [
                    if (picks.isEmpty)
                      const SetupRow(title: 'Using the defaults')
                    else
                      for (final pick in picks) SetupRow(title: pick.$1, subtitle: pick.$2),
                  ],
                ),
              ]),
            ),
          ],
          primary: flow.rerun ? 'Save' : 'Get started',
          onPrimary: () {
            if (!flow.rerun) HapticFeedback.lightImpact();
            flow.finish(context);
          },
        );
      },
    );
  }

  // only the answers that were given
  List<(String, String)> _picks(SetupFlowController flow) {
    final draft = flow.draft;
    HousingArea? area;
    for (final candidate in flow.areas) {
      if (candidate.id == draft.area) area = candidate;
    }
    final spots = draft.spots?.length ?? 0;
    final plan = TodayPlan.of(base: flow.dashboard, draft: draft);
    final cards = plan.cards.where((c) => !c.hidden).length;
    final profile = draft.profile == null ? null : profileById(draft.profile!);
    final clubs = draft.clubs?.length ?? 0;
    final room = draft.unit?.trim() ?? '';
    return [
      if (draft.scheme != null) ('Look', draft.scheme!.label),
      if (area != null) ('Where you live', room.isEmpty ? area.name : '${area.name}, $room'),
      if (spots > 0 || draft.hideDormSide == true)
        (
          'Your spots',
          [
            if (spots > 0) '$spots ${spots == 1 ? 'place' : 'places'}',
            if (draft.hideDormSide == true) 'Dorm side hidden',
          ].join(', '),
        ),
      if (profile != null || clubs > 0)
        (
          'Events',
          [
            ?profile?.name,
            if (clubs > 0) '$clubs ${clubs == 1 ? 'club' : 'clubs'} followed',
          ].join(', '),
        ),
      if (draft.hasToday || clubs > 0 || draft.homeIsNew || draft.spotsAreNew) ('Your Today', '$cards cards'),
    ];
  }
}
