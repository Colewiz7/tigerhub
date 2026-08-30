/// Everything about one dining location.
///
/// Reached by tapping a row. This is where the occupancy history finally
/// surfaces: the backend has been collecting a 24 hour series with today, the
/// same hour a week ago, and an average since the beginning, and nothing has
/// ever shown it.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api.dart';
import '../services/preferences.dart';
import '../theme/semantic.dart';
import '../theme/tokens.dart';
import '../widgets/freshness.dart';
import '../widgets/menu_section.dart';
import '../widgets/occupancy_chart.dart';
import '../services/subscriptions.dart';

class DiningDetailSheet extends StatefulWidget {
  const DiningDetailSheet({
    super.key,
    required this.location,
    required this.api,
  });

  final DiningLocation location;
  final ApiClient api;

  @override
  State<DiningDetailSheet> createState() => _DiningDetailSheetState();
}

class _DiningDetailSheetState extends State<DiningDetailSheet> {
  final _prefs = Preferences.instance;
  Result<OccupancyHistory>? _history;
  Result<MenuDay>? _menu;

  /// Held so they can be cancelled. Dangling subscriptions let a previous
  /// visit's results land after the current ones and overwrite them.
  final _subscriptions = Subscriptions();

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
    if (widget.location.occupancy != null) {
      _subscriptions.add(widget.api.occupancyHistory(widget.location.id).listen((r) {
        if (mounted) setState(() => _history = r);
      }));
    }
    _subscriptions.add(widget.api.menu(widget.location.id).listen((r) {
      if (mounted) setState(() => _menu = r);
    }));
  }

  @override
  void dispose() {
    _subscriptions.dispose();
    _prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final semantic = Semantic.of(context);
    final open = location.isOpen;
    final pinned = _prefs.isPinned(location.id);

    final hourly = _history?.value?.hourly ?? const <OccupancyHour>[];
    final nowHour = DateTime.now().hour;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(location.name,
                          style: text.titleLarge?.copyWith(fontSize: 24)),
                      if (location.summary != null) ...[
                        const SizedBox(height: 3),
                        Text(location.summary!, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _PinButton(
                  pinned: pinned,
                  onTap: () => _prefs.togglePinned(location.id),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status, stated plainly rather than left to a colour.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: Shapes.inner,
              ),
              child: Column(
                children: [
                  Text(
                    open
                        ? (location.closesAt == null
                            ? 'Open'
                            : 'Open until ${formatClock(location.closesAt!)}')
                        : (location.opensAt == null
                            ? 'Closed'
                            : 'Opens ${formatDayAndClock(location.opensAt!)}'),
                    textAlign: TextAlign.center,
                    style: text.displayMedium?.copyWith(
                      fontSize: 24,
                      fontVariations: Weights.medium,
                      color: open ? semantic.open : semantic.closed,
                    ),
                  ),
                  if (location.today.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      location.today
                          .map((s) =>
                              '${formatClock(s.opensAt)} to ${formatClock(s.closesAt)}')
                          .join(',  '),
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),

            if (location.occupancy != null) ...[
              const SizedBox(height: 20),
              Text('HOW BUSY', style: text.labelSmall),
              const SizedBox(height: 10),
              if (hourly.isEmpty)
                const PrimingPlaceholder(label: 'Loading occupancy')
              else ...[
                OccupancyChart(hourly: hourly, nowHour: nowHour),
                const SizedBox(height: 8),
                Text(
                  busynessCaption(hourly, nowHour, isOpen: open),
                  style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  'Live count from maps.rit.edu. Only five dining locations '
                  'have a sensor.',
                  style: text.bodySmall,
                ),
              ],
            ],

            if (_menu?.value != null && _menu!.value!.dishes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('ON THE MENU TODAY', style: text.labelSmall),
                  const Spacer(),
                  Text('${_menu!.value!.dishes.length}', style: text.labelSmall),
                ],
              ),
              const SizedBox(height: 10),
              MenuSection(menu: _menu!.value!, prefs: _prefs),
            ],

            if (location.description != null &&
                location.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('ABOUT', style: text.labelSmall),
              const SizedBox(height: 8),
              Text(_stripHtml(location.description!), style: text.bodyMedium),
            ],

            if (location.mapsUrl != null) ...[
              const SizedBox(height: 18),
              _LinkRow(
                icon: Icons.map_rounded,
                label: 'Open on the RIT campus map',
                url: location.mapsUrl!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The API sends the description as HTML, so it is flattened for display.
  static String _stripHtml(String raw) {
    final withoutTags = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.pinned, required this.onTap});

  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: pinned ? 'Unpin from the top' : 'Pin to the top',
      child: Material(
        elevation: 0,
        color: pinned ? scheme.primary : scheme.surfaceContainerHigh,
        shape: Shapes.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 16,
                  color: pinned ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(
                  pinned ? 'Pinned' : 'Pin',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: pinned ? scheme.onPrimary : scheme.onSurface,
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

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.url});

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // No url_launcher dependency, so the link is shown and copyable rather
    // than opened. Adding a package for one link is not worth it yet.
    return Tooltip(
      message: url,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.inner,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(url, style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
