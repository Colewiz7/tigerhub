/// Package pickup on Today: the counter for where you live, by its
/// scheduled hours. Holidays are not in the data, so it says scheduled.
library;

import 'package:flutter/material.dart';

import '../data/campus_time.dart';
import '../models/api_models.dart';
import '../services/api.dart';
import '../services/preferences.dart';
import '../services/todays_hours.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/card_shell.dart';
import '../widgets/compact_card.dart';
import '../widgets/status_row.dart';

String _clock(DateTime instant) {
  final f = CampusTime.fieldsOf(instant);
  return clockLabel(f.hour * 60 + f.minute);
}

/// The compact answer for the home [area] at the instant [now].
({String? value, String? caption, bool quiet}) packagePickupCompact({
  required List<HousingArea> areas,
  required List<PostOffice> offices,
  required String? area,
  required DateTime now,
}) {
  const none = (value: null, caption: null, quiet: true);
  if (area == null) return (value: 'Set home', caption: null, quiet: true);
  final home = areas.where((a) => a.id == area).firstOrNull;
  if (home == null) return none;
  if (home.directDelivery) return (value: 'Front desk', caption: null, quiet: true);
  final office = offices.where((o) => o.id == postOfficeFor(areas, area)).firstOrNull;
  if (office == null) return none;

  // fall back to every rule if a season is missing
  final season = currentSeason(CampusTime.fieldsOf(now));
  var rules = office.hours.where((r) => r.season == season).toList();
  if (rules.isEmpty) rules = office.hours;

  final today = todaysHours(service: 'package_pickup', rules: rules, now: now);
  switch (today.state) {
    case ServiceState.unknown:
      return none;
    case ServiceState.open:
      return (value: 'Until ${_clock(today.closesAt!)}', caption: 'Scheduled', quiet: false);
    case ServiceState.closedUntilLater:
      return (value: 'Opens ${_clock(today.opensAt!)}', caption: 'Scheduled', quiet: true);
    case ServiceState.closedForDay:
      final next = nextOpening(service: 'package_pickup', rules: rules, now: now);
      final tomorrow = CampusTime.dateOf(now).add(const Duration(days: 1));
      final isTomorrow = next != null && CampusTime.dateOf(next) == tomorrow;
      return (value: 'Closed today', caption: isTomorrow ? 'Opens ${_clock(next)} tomorrow' : 'Scheduled', quiet: true);
  }
}

class PackagePickupCard extends StatelessWidget {
  const PackagePickupCard({
    super.key,
    required this.areas,
    required this.offices,
    this.dragHandle,
    this.onShowAll,
  });

  final Result<Collection<HousingArea>> areas;
  final Result<Collection<PostOffice>> offices;
  final Widget? dragHandle;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Preferences.instance,
    builder: (context, _) {
      final answer = packagePickupCompact(
        areas: areas.value?.data ?? const [],
        offices: offices.value?.data ?? const [],
        area: Preferences.instance.homeArea,
        now: CampusTime.nowUtc(),
      );
      if (Insets.phone(context)) {
        return CompactCard(
          label: 'Package pickup',
          value: answer.value,
          caption: answer.caption,
          quiet: answer.quiet,
          dragHandle: dragHandle,
          onOpen: onShowAll,
          openLabel: 'opens Campus',
        );
      }
      return CardShell(
        title: 'Package pickup',
        glyph: AppIconKind.mail,
        dragHandle: dragHandle,
        child: StatusRow(
          icon: AppIconKind.mail,
          title: answer.value ?? '',
          subtitle: answer.caption,
          emphasis: answer.quiet ? RowEmphasis.dimmed : RowEmphasis.normal,
          onTap: onShowAll,
        ),
      );
    },
  );
}
