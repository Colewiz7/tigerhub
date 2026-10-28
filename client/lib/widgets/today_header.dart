/// Today's header: the mark and the gear, then the date as a large title.
///
/// Scrolled past, the date comes back short in a small bar with the gear.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';
import 'large_title.dart';

/// "Wednesday, October 14", wrapping rather than cut.
String todayLongDate(DateTime date) => DateFormat('EEEE, MMMM d').format(date);

/// "Wed, Oct 14", for the bar.
String todayShortDate(DateTime date) => DateFormat('EEE, MMM d').format(date);

class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key, required this.date, required this.onOpenSettings});

  final DateTime date;
  final VoidCallback onOpenSettings;

  /// The mark, a round 32.
  static const double markSize = 32;

  @override
  Widget build(BuildContext context) {
    final side = Insets.phone(context) ? Insets.phoneMargin : 26.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, 2, side - 10, 0),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/tigerhub-mascot.png',
                  width: markSize,
                  height: markSize,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
              const Spacer(),
              HeaderIconButton(
                icon: AppIconKind.settings,
                tooltip: 'Settings',
                label: 'Open settings',
                onTap: onOpenSettings,
              ),
            ],
          ),
        ),
        LargeTitle(todayLongDate(date)),
      ],
    );
  }
}

/// The short date and the gear, built once the large title has scrolled away.
class TodayCollapsedBar extends StatelessWidget {
  const TodayCollapsedBar({super.key, required this.date, required this.onOpenSettings});

  final DateTime date;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final side = Insets.phone(context) ? Insets.phoneMargin : 26.0;
    // opaque, no glass in content
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, 0, side - 10, 0),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  todayShortDate(date),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            HeaderIconButton(
              icon: AppIconKind.settings,
              tooltip: 'Settings',
              label: 'Open settings',
              onTap: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}
