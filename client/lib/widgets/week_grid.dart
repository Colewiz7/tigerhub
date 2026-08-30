/// A week of opening hours as a grid rather than a wall of text.
///
/// Seven rows, one per day, each showing the day's open periods as bars
/// positioned across a shared 24 hour scale. Reading "when is this open on
/// Wednesday" becomes looking at one row instead of parsing a sentence.
///
/// Multi-session days are the point: a facility with a morning and an evening
/// block shows two separated bars, which a text range cannot express without
/// listing both.
///
/// Colour carries nothing here. The bars are all the accent, and the day label
/// and the tooltip carry the meaning, so this stays readable regardless of
/// which palette is in force.
library;

import 'package:flutter/material.dart';


/// One open period, in minutes from midnight.
class DaySpan {
  const DaySpan({required this.startMinutes, required this.endMinutes, required this.label});

  final int startMinutes;
  final int endMinutes;
  final String label;
}

class WeekRow {
  const WeekRow({required this.label, required this.spans, this.note});

  final String label;
  final List<DaySpan> spans;

  /// Shown instead of bars when there are none, for example "Closed".
  final String? note;
}

class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.rows,
    this.highlightIndex,
    this.startHour = 6,
    this.endHour = 24,
  });

  final List<WeekRow> rows;

  /// Usually today, drawn with a stronger bar.
  final int? highlightIndex;

  /// The window the grid spans. Defaults to 6am to midnight, which is where
  /// campus hours actually live, so the bars are not squeezed into a third of
  /// the width by empty overnight hours.
  final int startHour;
  final int endHour;

  static const double _labelWidth = 96;
  static const double _rowHeight = 30;

  double _fraction(int minutes) {
    final from = startHour * 60;
    final to = endHour * 60;
    return ((minutes - from) / (to - from)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hour scale, labelled sparsely rather than every hour.
        Row(
          children: [
            const SizedBox(width: _labelWidth),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final hour in _ticks())
                    Text(_hourLabel(hour), style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++)
          SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Text(
                    rows[i].label,
                    style: i == highlightIndex
                        ? text.bodyMedium?.copyWith(color: scheme.primary)
                        : text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (rows[i].spans.isEmpty) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(rows[i].note ?? 'Closed',
                              style: text.bodySmall),
                        );
                      }
                      return Stack(
                        children: [
                          // The track, so an empty stretch still reads as a day.
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          for (final span in rows[i].spans)
                            Positioned(
                              left: _fraction(span.startMinutes) *
                                  constraints.maxWidth,
                              width: ((_fraction(span.endMinutes) -
                                          _fraction(span.startMinutes)) *
                                      constraints.maxWidth)
                                  .clamp(6.0, constraints.maxWidth),
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Tooltip(
                                  message: '${rows[i].label}  ${span.label}',
                                  child: Container(
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: i == highlightIndex
                                          ? scheme.primary
                                          : scheme.primary
                                              .withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<int> _ticks() {
    final span = endHour - startHour;
    final step = span > 12 ? 6 : 3;
    return [for (var h = startHour; h <= endHour; h += step) h];
  }

  static String _hourLabel(int hour) {
    if (hour == 0 || hour == 24) return '12a';
    if (hour == 12) return '12p';
    return hour < 12 ? '${hour}a' : '${hour - 12}p';
  }
}
