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
import '../../theme/tokens.dart';
import '../../widgets/status_row.dart';
import 'about_section.dart';
import 'appearance_section.dart';
import 'events_section.dart';
import 'home_section.dart';

enum SettingsSection { events, appearance, home, about }

typedef SettingsSpec = ({String title, String subtitle, IconData icon});

const Map<SettingsSection, SettingsSpec> settingsSections = {
  SettingsSection.events: (
    title: 'Events',
    subtitle: 'Organizer mutes, keyword rules',
    icon: Icons.event_note_rounded,
  ),
  SettingsSection.appearance: (
    title: 'Appearance',
    subtitle: 'Theme source, palette',
    icon: Icons.palette_rounded,
  ),
  SettingsSection.home: (
    title: 'Home screen',
    subtitle: 'Card order and visibility',
    icon: Icons.grid_view_rounded,
  ),
  SettingsSection.about: (
    title: 'About',
    subtitle: 'Version, data sources, disclaimer',
    icon: Icons.info_outline_rounded,
  ),
};

class SettingsScreen extends StatefulWidget {
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsSection? _selected;

  static const double twoPaneBreakpoint = 900;

  Widget _content(SettingsSection section) => switch (section) {
        SettingsSection.events =>
          EventsSection(events: widget.events.value?.data ?? const []),
        SettingsSection.appearance => AppearanceSection(scheme: widget.scheme),
        SettingsSection.home => HomeSection(
            cards: widget.cards,
            hidden: widget.hiddenCards,
            onChanged: widget.onCardsChanged,
          ),
        SettingsSection.about => const AboutSection(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= twoPaneBreakpoint;

    if (!wide) {
      // Narrow: one list that pushes to detail.
      return _NavList(
        selected: null,
        onSelect: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(settingsSections[section]!.title)),
              body: _content(section),
            ),
          ),
        ),
      );
    }

    final selected = _selected ?? SettingsSection.events;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 330,
          child: _NavList(
            selected: selected,
            onSelect: (section) => setState(() => _selected = section),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _content(selected),
          ),
        ),
      ],
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.selected, required this.onSelect});

  final SettingsSection? selected;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          for (final entry in settingsSections.entries)
            _NavRow(
              spec: entry.value,
              active: entry.key == selected,
              onTap: () => onSelect(entry.key),
            ),
        ],
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.spec, required this.active, required this.onTap});

  final SettingsSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Selection is a filled tinted container, not an underline.
    final background = active
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.surfaceContainerHigh;
    final badge =
        active ? scheme.primary : scheme.primary.withValues(alpha: 0.30);
    final iconColor = active ? scheme.onPrimary : scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: StatusRow.gap),
      child: Material(
        elevation: 0,
        color: background,
        borderRadius: Shapes.inner,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: StatusRow.badgeSize,
                  height: StatusRow.badgeSize,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: badge),
                  child: Icon(spec.icon, size: 21, color: iconColor),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(spec.title, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        spec.subtitle,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
