/// Settings.
///
/// Two panes on a wide window, a nav list on the left and content on the
/// right, collapsing to a single list that pushes to detail when narrow. Rows
/// use the same container plus circular icon badge pattern as everywhere else,
/// so there is one row style across the app.
library;

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/api.dart';
import '../../theme/dynamic_theme.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/section_nav.dart';
import 'about_section.dart';
import 'appearance_section.dart';
import 'campus_section.dart';
import 'dining_section.dart';
import 'events_section.dart';
import 'today_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.scheme,
    required this.events,
    this.onPersonalize,
  });

  final SchemeController scheme;
  final Result<Collection<CampusEvent>> events;

  /// Opens setup again, filled in. No row without it.
  final VoidCallback? onPersonalize;

  @override
  Widget build(BuildContext context) => SectionScaffold(
        actions: [
          if (onPersonalize != null)
            SectionAction(
              id: 'personalize',
              title: 'Personalize TigerHub',
              subtitle: 'Look, spots, events and Today',
              icon: AppIconKind.tune,
              onTap: onPersonalize!,
            ),
        ],
        sections: [
          SectionSpec(
            id: 'today',
            title: 'Today',
            subtitle: 'Smart order',
            icon: AppIconKind.todayTab,
            builder: (context) => const TodaySection(),
          ),
          SectionSpec(
            id: 'events',
            title: 'Events',
            subtitle: 'Profiles, mutes, keyword rules',
            icon: AppIconKind.events,
            builder: (context) =>
                EventsSection(events: events.value?.data ?? const []),
          ),
          SectionSpec(
            id: 'dining',
            title: 'Dining',
            subtitle: 'Dietary filters, allergens to flag',
            icon: AppIconKind.dining,
            builder: (context) => const DiningSection(),
          ),
          SectionSpec(
            id: 'campus',
            title: 'Campus',
            subtitle: 'Post offices, hidden rows',
            icon: AppIconKind.campus,
            builder: (context) => const CampusSection(),
          ),
          SectionSpec(
            id: 'appearance',
            title: 'Appearance',
            subtitle: 'Theme',
            icon: AppIconKind.appearance,
            builder: (context) => AppearanceSection(scheme: scheme),
          ),
          SectionSpec(
            id: 'about',
            title: 'About',
            subtitle: 'Version, data sources, disclaimer',
            icon: AppIconKind.info,
            builder: (context) => const AboutSection(),
          ),
        ],
      );
}
