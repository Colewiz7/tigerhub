/// The stale and failing indicators.
///
/// Deliberately quiet. A stale cache is normal, not an error, so this is one
/// line of small text and never a banner, a spinner, or a dimmed layout.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../theme/tokens.dart';

/// Relative age, formatting only. All real time logic lives on the server.
String formatAge(DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

/// Displays a timestamp the API computed. Never derives one.
///
/// Midnight and noon read better as words than as "12:00 AM", which is easy to
/// misread as midday.
String formatClock(DateTime when) {
  if (when.minute == 0 && when.hour == 0) return 'midnight';
  if (when.minute == 0 && when.hour == 12) return 'noon';
  return DateFormat('h:mm a').format(when);
}

String formatDayAndClock(DateTime when) =>
    '${DateFormat('EEE d MMM').format(when)}, ${formatClock(when)}';

class FreshnessLine extends StatelessWidget {
  const FreshnessLine({super.key, required this.state, this.fetchedAt});

  final DataState state;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    // Fresh data needs no annotation at all.
    if (state == DataState.ok || state == DataState.priming) {
      return const SizedBox.shrink();
    }
    if (fetchedAt == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final failing = state == DataState.failing;
    // Distinct roles: stale is muted, failing borrows the error role so the
    // two never read the same.
    final color = failing ? scheme.error : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (failing) ...[
            Icon(Icons.cloud_off_rounded, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            'updated ${formatAge(fetchedAt!)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// A content-shaped placeholder for first launch, when no cache exists yet.
///
/// It is deliberately static. Priming is usually over in about a second, so a
/// shimmer would start but rarely finish and make the wait feel longer.
class PrimingPlaceholder extends StatelessWidget {
  const PrimingPlaceholder({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = scheme.onSurface.withValues(alpha: 0.12);

    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _SkeletonRow(tint: tint, primaryFraction: 0.70),
              const SizedBox(height: 8),
              _SkeletonRow(tint: tint, primaryFraction: 0.52),
              const SizedBox(height: 8),
              _SkeletonRow(tint: tint, primaryFraction: 0.38),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.tint, required this.primaryFraction});

  final Color tint;
  final double primaryFraction;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: Shapes.inner,
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkeletonBar(
                  color: tint,
                  width: constraints.maxWidth * primaryFraction,
                  height: 12,
                ),
                const SizedBox(height: 7),
                _SkeletonBar(
                  color: tint,
                  width: constraints.maxWidth * primaryFraction * 0.72,
                  height: 9,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.color,
    required this.width,
    required this.height,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}
