/// About: version, where the data comes from, and the disclaimer.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/upstream.dart' show appVersion;
import '../../theme/tokens.dart';
import '../../widgets/status_row.dart';
import 'frame_stats_screen.dart';

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
  // ODbL requires this credit wherever the data is shown. It is not optional
  // and must not be dropped to tidy the list up.
  (
    name: 'OpenStreetMap',
    detail: 'Campus walking paths. Map data (c) OpenStreetMap contributors, ODbL',
    icon: Icons.directions_walk_rounded,
  ),
];

/// The app version. Tapping it five times in a row opens the frame stats.
/// Nothing on the row hints at that.
class VersionRow extends StatefulWidget {
  const VersionRow({super.key});

  /// Taps needed to open the stats screen.
  static const int taps = 5;

  /// The longest pause between taps that still counts as the same run.
  static const Duration window = Duration(milliseconds: 1000);

  @override
  State<VersionRow> createState() => _VersionRowState();
}

class _VersionRowState extends State<VersionRow> {
  int _count = 0;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _tap() {
    _reset?.cancel();
    _count++;
    if (_count >= VersionRow.taps) {
      _count = 0;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FrameStatsScreen()),
      );
      return;
    }
    _reset = Timer(VersionRow.window, () => _count = 0);
  }

  @override
  Widget build(BuildContext context) => StatusRow(
    icon: Icons.info_outline_rounded,
    title: 'Version',
    subtitle: appVersion,
    onTap: _tap,
  );
}

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
        const VersionRow(),
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
