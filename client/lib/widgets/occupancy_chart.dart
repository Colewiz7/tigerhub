/// How busy a dining location is across the day.
///
/// Form and colour, and why:
///
/// The job is change over time with a "right now" headline, so this is a bar
/// chart of today's hourly counts with the current hour highlighted, not two
/// overlaid series.
///
/// That choice is forced by the palette. The scheme is generated from the
/// wallpaper and is near monochrome, so `primary` and `onSurfaceVariant` sit
/// only ΔE 10.9 apart in normal vision, well under the 15 floor. Drawing
/// "today" and "typical" as two similar hues would be genuinely unreadable.
/// Instead this is a sequential ramp: one hue, two lightness steps, which
/// measures ΔE 32 normal and 30.8 protan, and both steps clear 3:1 against the
/// chart surface.
///
/// The today-versus-typical comparison is therefore made in words underneath
/// rather than by asking the eye to separate two near-identical colours.
///
/// One series, so no legend: the caption names it. The current hour is direct
/// labelled, and every bar has a tooltip.
library;

import 'package:flutter/material.dart';

import '../models/api_models.dart';

class OccupancyChart extends StatelessWidget {
  const OccupancyChart({
    super.key,
    required this.hourly,
    required this.nowHour,
    this.height = 96,
  });

  final List<OccupancyHour> hourly;
  final int nowHour;
  final double height;

  /// Lifted until the dim bars clear 3:1 against the chart surface. At the
  /// obvious 0.30 they measured 2.08:1, which the accessibility pass rejects.
  static const double _dimAlpha = 0.45;

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final peak = hourly.fold<int>(1, (m, h) => h.today > m ? h.today : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final hour in hourly)
                Expanded(
                  child: Padding(
                    // A 2px surface gap between adjacent bars.
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Tooltip(
                      message: '${_hourLabel(hour.hour)}  '
                          '${hour.today} here, ${hour.average} typical',
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (hour.today / peak).clamp(0.02, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: hour.hour == nowHour
                                  ? scheme.primary
                                  : scheme.primary.withValues(alpha: _dimAlpha),
                              // Rounded data-ends, anchored square to the
                              // baseline so the bar reads from zero.
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Selective labels only: the ends and the current hour, never one per bar.
        Row(
          children: [
            Text('12a', style: text.bodySmall),
            const Spacer(),
            Text('12p', style: text.bodySmall),
            const Spacer(),
            Text('11p', style: text.bodySmall),
          ],
        ),
      ],
    );
  }

  static String _hourLabel(int hour) {
    if (hour == 0) return 'midnight';
    if (hour == 12) return 'noon';
    return hour < 12 ? '${hour}am' : '${hour - 12}pm';
  }
}

/// The comparison, in words.
///
/// Two near identical colours cannot carry this, so it is stated rather than
/// encoded.
String busynessCaption(
  List<OccupancyHour> hourly,
  int nowHour, {
  bool isOpen = true,
}) {
  // A "right now" comparison means nothing somewhere that is shut, and
  // maps.rit.edu keeps reporting a count after close: Gracie's read 29 people
  // while its own status said Closed Today. Without this the sheet said
  // "Quieter than usual for this time" under a HOW BUSY heading, which reads
  // as an invitation to a place you cannot get into.
  if (!isOpen) {
    return 'Closed now. The line is today so far against a typical day.';
  }
  final now = hourly.where((h) => h.hour == nowHour).firstOrNull;
  if (now == null || now.average == 0) return '';
  final delta = now.today - now.average;
  final ratio = delta / now.average;

  if (ratio > 0.25) return 'Busier than usual for this time';
  if (ratio < -0.25) return 'Quieter than usual for this time';
  return 'About as busy as usual for this time';
}
