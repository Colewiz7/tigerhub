/// Section icons: Cupertino on iOS, Material everywhere else.
///
/// One enum per meaning, so a section names what it is and the platform picks
/// the drawing. SF Symbol files are never bundled, Apple's license forbids it,
/// so iOS gets the CupertinoIcons font, which follows the same style.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

enum AppIconKind {
  // cupertino has no fork and knife, same as the tab bar
  dining(Icons.restaurant_rounded, Icons.restaurant_rounded),
  events(CupertinoIcons.tickets, Icons.event_note_rounded),
  calendar(CupertinoIcons.calendar, Icons.calendar_month_rounded),
  mail(CupertinoIcons.envelope, Icons.local_post_office_rounded),
  find(CupertinoIcons.map_pin_ellipse, Icons.travel_explore_rounded),
  makerspace(CupertinoIcons.hammer, Icons.construction_rounded),
  buildings(CupertinoIcons.building_2_fill, Icons.apartment_rounded),
  // no chef hat in either set
  visitingChef(Icons.soup_kitchen_rounded, Icons.soup_kitchen_rounded);

  const AppIconKind(this.cupertino, this.material);

  final IconData cupertino;
  final IconData material;

  IconData of(BuildContext context) => Theme.of(context).platform == TargetPlatform.iOS ? cupertino : material;
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.kind, {super.key, this.size = 18, this.color});

  final AppIconKind kind;
  final double size;

  /// Defaults to the surrounding text colour, so the icon matches its label.
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
    kind.of(context),
    size: size,
    color: color ?? DefaultTextStyle.of(context).style.color,
  );
}
