/// Step 5: events. A taste for the events list, and the clubs to follow.
library;

import 'package:flutter/material.dart';

import '../../services/filter_profiles.dart';
import '../../services/setup_draft.dart';
import '../../motion/reduce_motion.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/focus_ring.dart';
import '../../widgets/search_field.dart';
import 'setup_kit.dart';

// one line each, the preset's own description is two sentences
const Map<String, String> _lines = {
  'free_and_fun': 'Free food, games and music first',
  'academic': 'Workshops and career events first',
  'quiet': 'Fewer recurring meetings',
  'everything': 'No keyword rules',
};

class EventsStep extends StatelessWidget {
  const EventsStep({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final clubs = flow.draft.clubs ?? const <String>{};
        final noEvents = organizersOf(flow.events).isEmpty && clubs.isEmpty;
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.events),
          title: 'Events',
          subtitle: 'Pick what your events list favors.',
          leading: flow.leadingFor(context, SetupStep.events),
          trailing: flow.trailingFor(context),
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                for (final profile in builtInProfiles)
                  _ProfileCard(
                    profile: profile,
                    selected: flow.draft.profile == profile.id,
                    onTap: () {
                      setupSelect();
                      flow.draft.setProfile(profile.id);
                    },
                  ),
                const SizedBox(height: 8),
                SetupGroup(
                  children: [
                    SetupRow(
                      title: 'Follow a club',
                      subtitle: noEvents
                          ? 'Events unavailable'
                          : clubs.isEmpty
                          ? null
                          : '${clubs.length} followed',
                      onTap: noEvents
                          ? null
                          : () => Navigator.of(context).push(setupRoute<void>(context, (_) => flow.wrap(const ClubSearch()))),
                      trailing: AppIcon(AppIconKind.chevron, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ]),
            ),
          ],
          primary: setupPrimaryLabel(chosen: flow.draft.hasEvents),
          onPrimary: () => flow.next(context, SetupStep.events),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.selected, required this.onTap});

  final FilterProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final line = _lines[profile.id] ?? profile.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        checked: selected,
        label: '${profile.name}, $line',
        excludeSemantics: true,
        onTap: onTap,
        child: FocusRing(
          radius: Shapes.innerRadius,
          builder: (onFocusChange) => Material(
            elevation: 0,
            color: scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: Shapes.inner,
              side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onFocusChange: onFocusChange,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? scheme.primary : scheme.primary.withValues(alpha: 0.3),
                          ),
                          child: Center(
                            child: AppIcon(profile.icon, size: 22, color: selected ? scheme.onPrimary : scheme.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.name, style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(line, style: text.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _Radio(selected: selected),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(color: selected ? scheme.primary : scheme.onSurfaceVariant, width: 1.5),
      ),
      child: selected ? AppIcon(AppIconKind.check, size: 15, color: scheme.onPrimary) : null,
    );
  }
}

/// The club search, pushed over the Events step.
class ClubSearch extends StatefulWidget {
  const ClubSearch({super.key});

  @override
  State<ClubSearch> createState() => _ClubSearchState();
}

class _ClubSearchState extends State<ClubSearch> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final clubs = flow.draft.clubs ?? const <String>{};
        final known = organizersOf(flow.events);
        final names = {for (final o in known) o.key: o.name};
        final needle = _query.text.trim().toLowerCase();
        final shown = [
          for (final o in known)
            if (needle.isEmpty || o.name.toLowerCase().contains(needle)) o,
        ];
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.groups),
          title: 'Follow a club',
          subtitle: 'Each club you follow gets a card on Today.',
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SearchField(
                    controller: _query,
                    focusNode: _focus,
                    hintText: 'Search clubs',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: EmptyState(kind: EmptyKind.notFound, title: 'No matches'),
                  )
                else
                  SetupGroup(
                    children: [
                      for (final club in shown)
                        SetupRow(
                          title: club.name,
                          selected: clubs.contains(club.key),
                          semanticsLabel: '${club.name}, ${clubs.contains(club.key) ? 'followed' : 'not followed'}',
                          trailing: SetupCheck(shown: clubs.contains(club.key)),
                          onTap: () {
                            setupSelect();
                            if (clubs.contains(club.key)) {
                              flow.draft.unfollowClub(club.key);
                            } else {
                              flow.draft.followClub(club.key, names[club.key] ?? club.name);
                            }
                          },
                        ),
                    ],
                  ),
              ]),
            ),
          ],
          primary: 'Done',
          onPrimary: () => Navigator.of(context).pop(),
        );
      },
    );
  }
}
