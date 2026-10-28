/// Shuttles on Today: how many routes still run from home, and until when.
///
/// Built from RIT's published service windows. Nothing here knows a
/// departure, so the card never says when the next bus comes.
library;

import 'package:flutter/material.dart';

import '../data/campus_time.dart';
import '../data/shuttles.dart';
import '../services/preferences.dart';
import '../services/todays_hours.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/card_shell.dart';
import '../widgets/compact_card.dart';
import '../widgets/status_row.dart';

/// The compact answer for [area] at the campus wall clock [now].
({String? value, String? caption, bool quiet}) shuttlesCompact(ShuttleSchedule? schedule, String? area, DateTime now) {
  if (area == null) return (value: 'Set home', caption: null, quiet: true);
  if (schedule == null) return (value: null, caption: null, quiet: true);
  if (!schedule.covers(area) && schedule.holidayOn(now) == null) return (value: 'No routes', caption: null, quiet: true);
  final window = schedule.windowAt(area, now);
  String routes(int n) => n == 1 ? '1 route' : '$n routes';
  return switch (window.state) {
    ShuttleState.running => (value: routes(window.routes), caption: 'until ${clockLabel(window.minute!)}', quiet: false),
    ShuttleState.before => (value: routes(window.routes), caption: 'from ${clockLabel(window.minute!)}', quiet: true),
    ShuttleState.done => (value: 'Done today', caption: null, quiet: true),
    ShuttleState.none => (value: 'None today', caption: null, quiet: true),
  };
}

class ShuttlesCard extends StatelessWidget {
  const ShuttlesCard({super.key, this.dragHandle, this.onShowAll});

  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ShuttleSchedule.current, Preferences.instance]),
    builder: (context, _) {
      final answer = shuttlesCompact(ShuttleSchedule.current.value, Preferences.instance.homeArea, CampusTime.wallNow());
      if (Insets.phone(context)) {
        return CompactCard(
          label: 'Shuttles',
          value: answer.value,
          caption: answer.caption,
          quiet: answer.quiet,
          dragHandle: dragHandle,
          onOpen: onShowAll,
          openLabel: 'opens Campus',
        );
      }
      return CardShell(
        title: 'Shuttles',
        glyph: AppIconKind.shuttle,
        dragHandle: dragHandle,
        child: StatusRow(
          icon: AppIconKind.shuttle,
          title: answer.value ?? '',
          subtitle: answer.caption,
          emphasis: answer.quiet ? RowEmphasis.dimmed : RowEmphasis.normal,
          onTap: onShowAll,
        ),
      );
    },
  );
}
