/// Pin, hide and move actions for a dining row, and the group picker sheet.
library;

import 'package:flutter/material.dart';

import '../data/dining_display_names.dart';
import '../data/dining_layout.dart';
import '../data/static_config.dart';
import '../models/api_models.dart';
import '../services/clipboard.dart';
import '../services/preferences.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
import 'context_actions.dart';

const moveToGroupLabel = 'Move to group';

List<MenuAction> diningActions(DiningLocation location) {
  final prefs = Preferences.instance;
  final pinned = prefs.isPinned(location.id);
  final hidden = prefs.isHidden(location.id);
  return [
    // a hidden place is unhidden before it can be pinned
    if (!hidden)
      MenuAction(
        label: pinned ? 'Unpin' : 'Pin',
        icon: AppIconKind.pinned,
        onSelected: (_) => prefs.togglePinned(location.id),
      ),
    MenuAction(
      label: hidden ? 'Unhide' : 'Hide',
      icon: AppIconKind.hidden,
      onSelected: (context) {
        if (hidden) {
          prefs.toggleHidden(location.id);
          return;
        }
        // the row leaves the list once hidden, so speak first
        final key = '${location.id}';
        final wasPinned = prefs.isPinned(location.id);
        showFeedback(
          context,
          'Hid ${locationDisplayName(location)}',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => prefs.restoreDining(
              pinned: {...prefs.pinnedDining, if (wasPinned) key},
              hidden: {...prefs.hiddenDining}..remove(key),
            ),
          ),
        );
        prefs.toggleHidden(location.id);
      },
    ),
    MenuAction(
      label: moveToGroupLabel,
      icon: AppIconKind.allPlaces,
      onSelected: (context) => showMoveToGroupSheet(context, location),
    ),
  ];
}

// every group, with the one the place is in now marked
List<ResolvedGroup> groupsFor(DiningLocation location) {
  final config = StaticConfig.loadedOrNull;
  return Preferences.instance.diningLayout.resolve(
    defaults: config?.diningGroups ?? const [],
    defaultGroupOf: config?.diningGroupFor ?? (_) => otherGroupId,
    placeIds: [location.id],
  );
}

Future<void> showMoveToGroupSheet(BuildContext context, DiningLocation location) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: scheme.surfaceContainerLow,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Shapes.cardRadius))),
    builder: (_) => _MoveSheet(location: location),
  );
}

class _MoveSheet extends StatelessWidget {
  const _MoveSheet({required this.location});

  final DiningLocation location;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final groups = groupsFor(location);
    final current = groups.firstWhere((g) => g.placeIds.isNotEmpty, orElse: () => groups.last).id;
    final config = StaticConfig.loadedOrNull;
    final home = config?.diningGroupFor(location.id) ?? otherGroupId;
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(moveToGroupLabel, style: text.titleLarge),
              ),
            ),
            for (final group in groups)
              Semantics(
                button: true,
                selected: group.id == current,
                label: group.name,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: Shapes.inner,
                  onTap: () {
                    final prefs = Preferences.instance;
                    prefs.setDiningLayout(prefs.diningLayout.move(location.id, group.id, defaultGroup: home));
                    Navigator.of(context).pop();
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(group.name, style: text.bodyLarge)),
                          if (group.id == current) AppIcon(AppIconKind.check, size: 20, color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
