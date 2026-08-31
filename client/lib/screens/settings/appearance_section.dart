/// Appearance: where the palette comes from.
library;

import 'package:flutter/material.dart';

import '../../theme/dynamic_theme.dart';
import '../../theme/scheme_source.dart';
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
              Text(
                'Theme source',
                style: text.titleLarge?.copyWith(fontSize: 21),
              ),
              const SizedBox(height: 4),
              Text(
                "The app's own palette is the default. It is designed for "
                'readability and validated for colour vision deficiency, and it '
                'is the same everywhere the app runs.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        StatusRow(
          icon: Icons.palette_rounded,
          title: 'Built-in palette',
          subtitle: 'RIT orange, light and dark, follows your system setting',
          emphasis: state.isDynamic ? RowEmphasis.dimmed : RowEmphasis.normal,
          onTap: () => widget.scheme.setForceSeed(true),
          trailing: state.isDynamic
              ? null
              : Icon(Icons.check_circle_rounded, color: scheme.primary),
        ),
        // Desktop only, and hidden rather than merely disabled elsewhere.
        // Following the wallpaper reads a scheme file that a Linux desktop
        // shell writes. On Android there is no such file and no HOME to look
        // under, so the row could never do anything, and a switch that cannot
        // work is worse than an absent one.
        if (schemeSourceIsAvailable)
          StatusRow(
            icon: Icons.wallpaper_rounded,
            title: 'Follow my wallpaper',
            subtitle: state.isDynamic
                ? (state.detail ?? 'reading the generated scheme')
                : 'Linux desktop only, needs a generated scheme file',
            emphasis: state.isDynamic ? RowEmphasis.normal : RowEmphasis.dimmed,
            onTap: () => widget.scheme.setForceSeed(false),
            trailing: state.isDynamic
                ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                : null,
          ),
        const SizedBox(height: 18),
        if (schemeSourceIsAvailable)
          Text(
            'Following the wallpaper is off by default. A generated scheme is '
            'whatever a photo happened to contain, so it is not a design, and it '
            'can produce colours that are unreadable or that clash with the '
            'status colours. Turn it on if you like it on your own machine.\n\n'
            'The same switch is on the palette button in the app bar. A build can '
            'pin the built-in palette outright with --dart-define=FORCE_SEED=true.',
            style: text.bodySmall,
          ),
      ],
    );
  }
}
