/// Today's shuttle routes for the home area, opened from the Shuttles card.
///
/// Scheduled windows only. Nothing here knows a departure, so live vehicles
/// are left to TripShot.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/campus_time.dart';
import '../data/shuttles.dart';
import '../data/static_config.dart';
import '../services/preferences.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
import 'context_actions.dart';
import 'empty_state.dart';
import 'status_row.dart';

Future<void> showShuttleRoutesSheet(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: scheme.surfaceContainerLow,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 720),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Shapes.cardRadius))),
    builder: (_) => const ShuttleRoutesSheet(),
  );
}

class ShuttleRoutesSheet extends StatelessWidget {
  const ShuttleRoutesSheet({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ShuttleSchedule.current, Preferences.instance]),
    builder: (context, _) => _build(context, ShuttleSchedule.current.value),
  );

  Widget _build(BuildContext context, ShuttleSchedule? schedule) {
    final text = Theme.of(context).textTheme;
    final homeId = Preferences.instance.homeArea;
    final homeName = homeId == null ? null : StaticConfig.loadedOrNull?.area(homeId)?['name'] as String?;
    final clock = now ?? CampusTime.wallNow();
    final holiday = schedule?.holidayOn(clock);
    final breakDays = schedule?.breakOn(clock);
    final routes = schedule?.routesOn(homeId, clock) ?? const <ShuttleRoute>[];

    final title = holiday != null
        ? '${holiday.name} service'
        : breakDays != null
        ? '${breakDays.name} service'
        : 'Today from ${homeName ?? 'home'}';
    final subtitle = holiday != null
        ? 'Reduced service published for ${DateFormat('EEEE, MMMM d').format(clock)}.'
        : breakDays != null
        ? 'Break shuttle only. Scheduled windows, not live arrivals.'
        : 'Scheduled windows, not live arrivals. Arrive at the stop at least five minutes early.';

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
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Text(title, style: text.titleLarge),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(subtitle, style: text.bodySmall),
            ),
            if (homeId == null)
              const EmptyState(kind: EmptyKind.notFound, title: 'Set your housing area', compact: false)
            // the table is still loading
            else if (schedule == null)
              const SizedBox.shrink()
            else if (holiday == null && !schedule.covers(homeId))
              const EmptyState(kind: EmptyKind.notFound, title: 'No routes for this area', compact: false)
            else if (routes.isEmpty)
              const EmptyState(kind: EmptyKind.noEvents, title: 'No routes today', compact: false)
            else
              for (final route in routes)
                StatusRow(
                  icon: AppIconKind.shuttle,
                  iconSize: StatusRow.fillIconSize,
                  wrapSubtitle: true,
                  title: '${route.number} · ${route.name}',
                  subtitle: route.hours,
                  actions: [MenuAction.copy('${route.number} · ${route.name}\n${route.hours}')],
                ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Live vehicle locations and arrival estimates are available in TripShot.', style: text.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
