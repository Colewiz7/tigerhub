/// Appearance: where the palette comes from.
library;

import 'package:flutter/material.dart';

import '../../theme/dynamic_theme.dart';
import '../../widgets/status_row.dart';

class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key, required this.scheme});

  final SchemeController scheme;

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  @override
  void initState() {
    super.initState();
    widget.scheme.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.scheme.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.scheme.state;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme source', style: text.titleLarge?.copyWith(fontSize: 21)),
              const SizedBox(height: 4),
              Text(
                'The palette is generated from your wallpaper by Caelestia. '
                'Pin the built-in palette if a wallpaper ever produces '
                'something unreadable.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        StatusRow(
          icon: Icons.wallpaper_rounded,
          title: 'Follow the wallpaper',
          subtitle: state.isDynamic
              ? (state.detail ?? 'reading the generated scheme')
              : 'not currently in use',
          emphasis: state.isDynamic ? RowEmphasis.normal : RowEmphasis.dimmed,
          onTap: () => widget.scheme.setForceSeed(false),
          trailing: state.isDynamic
              ? Icon(Icons.check_circle_rounded, color: scheme.primary)
              : null,
        ),
        StatusRow(
          icon: Icons.lock_outline_rounded,
          title: 'Pin the built-in palette',
          subtitle: 'RIT orange, known good, ignores the wallpaper',
          emphasis: state.isDynamic ? RowEmphasis.dimmed : RowEmphasis.normal,
          onTap: () => widget.scheme.setForceSeed(true),
          trailing: state.isDynamic
              ? null
              : Icon(Icons.check_circle_rounded, color: scheme.primary),
        ),
        const SizedBox(height: 18),
        Text(
          'The same switch is available from the palette button in the app bar. '
          'A build can also pin it with --dart-define=FORCE_SEED=true.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
