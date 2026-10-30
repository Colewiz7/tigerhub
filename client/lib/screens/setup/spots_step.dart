/// Step 4: your spots. Every dining place as a tile under its group, and the
/// switch that hides the dorm side.
library;

import 'package:flutter/material.dart';

import '../../cards/dining_card.dart' show iconForVenue;
import '../../data/dining_layout.dart';
import '../../data/static_config.dart';
import '../../models/api_models.dart';
import '../../motion/reduce_motion.dart';
import '../../services/preferences.dart';
import '../../services/setup_draft.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/focus_ring.dart';
import 'setup_kit.dart';

class SpotsStep extends StatelessWidget {
  const SpotsStep({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = SetupScope.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // two across once text is large, so names keep their room
    final columns = scale >= 1.5 ? 2 : 3;

    return ListenableBuilder(
      listenable: flow.draft,
      builder: (context, _) {
        final dormOn = flow.draft.hideDormSide ?? false;
        final picked = flow.draft.spots ?? const <String>{};
        final sections = _sections(flow.dining);
        return SetupPage(
          badge: const SetupBadge(glyph: AppIconKind.dining),
          title: 'Your spots',
          subtitle: 'These show first in Dining and on Today.',
          leading: flow.leadingFor(context, SetupStep.spots),
          trailing: flow.trailingFor(context),
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                SetupGroup(
                  children: [
                    SetupRow(
                      title: 'Hide Dorm side',
                      subtitle: _dormNames(),
                      selected: dormOn,
                      semanticsLabel: 'Hide Dorm side, ${dormOn ? 'on' : 'off'}',
                      onTap: () {
                        setupSelect();
                        flow.draft.setHideDormSide(!dormOn);
                      },
                      trailing: ExcludeSemantics(
                        child: Switch(
                          value: dormOn,
                          onChanged: (value) {
                            setupSelect();
                            flow.draft.setHideDormSide(value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                if (flow.dining.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(kind: EmptyKind.sourceDown, title: 'Dining unavailable'),
                  ),
                for (final section in sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Semantics(
                      header: true,
                      child: Text(section.name, style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                  _SpotGrid(
                    places: section.places,
                    picked: picked,
                    columns: columns,
                    onTap: (place) {
                      setupSelect();
                      flow.draft.toggleSpot('${place.id}');
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ],
          primary: setupPrimaryLabel(chosen: flow.draft.hasSpots),
          onPrimary: () => flow.next(context, SetupStep.spots),
        );
      },
    );
  }

  // the places the hide switch covers, by name
  String? _dormNames() {
    final config = StaticConfig.loadedOrNull;
    final ids = config?.diningGroupHideIds[dormSideGroupId];
    if (config == null || ids == null) return null;
    final names = {for (final p in config.diningGroupPlaces) p.id: p.name};
    return [for (final id in ids) names[id] ?? '$id'].join(', ');
  }

  // current group headers, empty ones left out
  List<({String name, List<DiningLocation> places})> _sections(List<DiningLocation> dining) {
    final config = StaticConfig.loadedOrNull;
    final byId = {for (final l in dining) l.id: l};
    final groups = Preferences.instance.diningLayout.resolve(
      defaults: config?.diningGroups ?? const [],
      defaultGroupOf: config?.diningGroupFor ?? (_) => otherGroupId,
      placeIds: [for (final l in dining) l.id],
    );
    return [
      for (final group in groups)
        if (group.placeIds.isNotEmpty)
          (
            name: group.name,
            places: [for (final id in group.placeIds) byId[id]!]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
          ),
    ];
  }
}

class _SpotGrid extends StatelessWidget {
  const _SpotGrid({required this.places, required this.picked, required this.columns, required this.onTap});

  final List<DiningLocation> places;
  final Set<String> picked;
  final int columns;
  final ValueChanged<DiningLocation> onTap;

  @override
  Widget build(BuildContext context) {
    // rows grow to the tallest name, so large text never cuts one off
    final rows = <Widget>[];
    for (var i = 0; i < places.length; i += columns) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++)
                Expanded(
                  child: i + c < places.length
                      ? _Tile(
                          place: places[i + c],
                          selected: picked.contains('${places[i + c].id}'),
                          onTap: () => onTap(places[i + c]),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.place, required this.selected, required this.onTap});

  final DiningLocation place;
  final bool selected;
  final VoidCallback onTap;

  static const double circle = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1;
    final duration = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 160);
    return Semantics(
      button: true,
      selected: selected,
      label: place.name,
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        radius: 16,
        builder: (onFocusChange) => InkWell(
          onTap: onTap,
          onFocusChange: onFocusChange,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: circle + 6,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: duration,
                        width: circle,
                        height: circle,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
                        ),
                        child: Icon(
                          iconForVenue(place.name).of(context),
                          size: 26,
                          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: SizedBox.square(
                                dimension: 20,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
                                  child: AppIcon(AppIconKind.check, size: 13, color: scheme.onPrimary),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  place.name,
                  textAlign: TextAlign.center,
                  maxLines: large ? null : 2,
                  overflow: large ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontSize: 13, height: 1.2, color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
