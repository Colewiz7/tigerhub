/// The stale and failing indicators.
///
/// Deliberately quiet. A stale cache is normal, not an error, so this is one
/// line of small text and never a banner, a spinner, or a dimmed layout.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';


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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The only place a spinner is correct: first launch, never had data.
class PrimingPlaceholder extends StatelessWidget {
  const PrimingPlaceholder({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
