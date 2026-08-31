/// First run: ask where you live, once.
///
/// This is the only thing the app ever asks for, and it earns its place because
/// the answer is reused everywhere. It is the second line of your mailing
/// address, and it is the anchor anything "nearest to me" would sort against.
///
/// **It does not block the app.** Skipping leaves everything working, the
/// housing card falls back to asking in place, and the question is not asked
/// again. An app that will not open until a form is filled in is worse than one
/// that never asked.
///
/// It also does not wait on the network. The housing areas come from bundled
/// config (docs/notes.md 7.9: RIT's mail is zone based, so the areas are a fixed
/// list, not a feed), which means first run works with no connection at all.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/preferences.dart';
import '../theme/tokens.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.areas,
    required this.onDone,
  });

  final List<HousingArea> areas;

  /// Called once the answer is stored, or once it is skipped.
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String? _area;
  final _unit = TextEditingController();

  @override
  void dispose() {
    _unit.dispose();
    super.dispose();
  }

  HousingArea? get _selected {
    for (final area in widget.areas) {
      if (area.id == _area) return area;
    }
    return null;
  }

  Future<void> _finish({required bool skipped}) async {
    if (!skipped && _area != null) {
      await Preferences.instance.setHome(
        area: _area,
        unit: _unit.text.trim(),
      );
    }
    await Preferences.instance.markSetupSeen();
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selected = _selected;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Where do you live?', style: text.displaySmall),
                const SizedBox(height: 8),
                Text(
                  'Used for your mailing address. You can change it any time, '
                  'and you can skip this.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final area in widget.areas)
                      _AreaChoice(
                        label: area.name,
                        selected: area.id == _area,
                        onTap: () => setState(() => _area = area.id),
                      ),
                  ],
                ),

                // Only once an area is picked, because the format shown in the
                // hint is per area and meaningless before then.
                if (selected != null && !selected.directDelivery) ...[
                  const SizedBox(height: 22),
                  Text('YOUR BUILDING AND ROOM', style: text.labelSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _unit,
                    decoration: InputDecoration(
                      hintText: selected.line2Example ?? 'Building and room',
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: Shapes.inner,
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (_) => _finish(skipped: false),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Optional. Without it the address shows the format instead.',
                    style: text.bodySmall,
                  ),
                ],

                // RIT runs a zone based system with no mailbox numbers, and
                // two locations bypass the campus post offices entirely.
                if (selected != null && selected.directDelivery) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Mail goes straight to the property here, not through a '
                    'campus post office.',
                    style: text.bodySmall,
                  ),
                ],

                const SizedBox(height: 28),
                Row(
                  children: [
                    FilledButton(
                      onPressed:
                          _area == null ? null : () => _finish(skipped: false),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _finish(skipped: true),
                      style: TextButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaChoice extends StatelessWidget {
  const _AreaChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      elevation: 0,
      color: selected
          ? scheme.primary.withValues(alpha: 0.22)
          : scheme.surfaceContainerHigh,
      shape: Shapes.pill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
