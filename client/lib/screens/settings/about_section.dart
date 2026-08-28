/// About: version, where the data comes from, and the disclaimer.
library;

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_row.dart';

const _sources = <({String name, String detail, IconData icon})>[
  (
    name: 'TigerCenter',
    detail: 'Dining locations, hours, visiting chefs',
    icon: Icons.restaurant_rounded,
  ),
  (
    name: 'CampusGroups',
    detail: 'Student club events, public iCal feed',
    icon: Icons.groups_rounded,
  ),
  (
    name: 'RIT Drupal JSON:API',
    detail: 'Official university events',
    icon: Icons.school_rounded,
  ),
  (
    name: 'make.rit.edu',
    detail: 'SHED equipment availability',
    icon: Icons.construction_rounded,
  ),
  (
    name: 'maps.rit.edu',
    detail: 'Live occupancy, 5 dining locations have sensors',
    icon: Icons.map_rounded,
  ),
];

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppConfig.appName, style: text.titleLarge?.copyWith(fontSize: 26)),
              const SizedBox(height: 4),
              Text('API: ${AppConfig.apiBaseUrl}', style: text.bodySmall),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: Shapes.inner,
          ),
          child: Text(AppConfig.disclaimer, style: text.bodyMedium),
        ),
        const SizedBox(height: 22),
        Text('DATA SOURCES', style: text.labelSmall),
        const SizedBox(height: 10),
        for (final source in _sources)
          StatusRow(
            icon: source.icon,
            title: source.name,
            subtitle: source.detail,
          ),
        const SizedBox(height: 12),
        Text(
          'All data is public and cached on a schedule. No login gated endpoint '
          'is ever contacted, and no credentials are stored.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
