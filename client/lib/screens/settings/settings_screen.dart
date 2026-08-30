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
import '../../widgets/section_nav.dart';
import 'about_section.dart';
import 'appearance_section.dart';
import 'dining_section.dart';
import 'events_section.dart';
import 'home_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.scheme,
    required this.events,
    required this.cards,
    required this.hiddenCards,
    required this.onCardsChanged,
  });

  final SchemeController scheme;
  final Result<Collection<CampusEvent>> events;
  final List<String> cards;
  final List<String> hiddenCards;
  final void Function(List<String> order, List<String> hidden) onCardsChanged;

  @override
  Widget build(BuildContext context) => SectionScaffold(
        sections: [
          SectionSpec(
            id: 'events',
            title: 'Events',
            subtitle: 'Profiles, organizer mutes, keyword rules',
            icon: Icons.event_note_rounded,
            builder: (context) =>
                EventsSection(events: events.value?.data ?? const []),
          ),
          SectionSpec(
            id: 'dining',
            title: 'Dining',
            subtitle: 'Dietary filters, allergens to flag',
            icon: Icons.restaurant_rounded,
            builder: (context) => const DiningSection(),
          ),
          SectionSpec(
            id: 'appearance',
            title: 'Appearance',
            subtitle: 'Theme source, palette',
            icon: Icons.palette_rounded,
            builder: (context) => AppearanceSection(scheme: scheme),
          ),
          SectionSpec(
            id: 'home',
            title: 'Home screen',
            subtitle: 'Card order and visibility',
            icon: Icons.grid_view_rounded,
            builder: (context) => HomeSection(
              cards: cards,
              hidden: hiddenCards,
              onChanged: onCardsChanged,
            ),
          ),
          SectionSpec(
            id: 'about',
            title: 'About',
            subtitle: 'Version, data sources, disclaimer',
            icon: Icons.info_outline_rounded,
            builder: (context) => const AboutSection(),
          ),
        ],
      );
}
