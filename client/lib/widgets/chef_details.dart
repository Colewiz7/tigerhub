/// The time and the location of a visiting chef, one line each.
///
/// The Today card used to join both into one subtitle capped at two lines, so
/// the location (written last) was the first thing an ellipsis took. Here each
/// is its own line and neither is ever cut: a long one wraps. From 600pt the
/// card budgets a fixed row height that is pinned to the base layout, so
/// [wrap] is off there and both share one line, as they always did.
library;

import 'package:flutter/material.dart';

import 'status_text.dart';

class ChefDetails extends StatelessWidget {
  const ChefDetails({
    super.key,
    required this.window,
    required this.location,
    required this.style,
    this.locationColor,
    this.wrap = true,
  });

  /// The location's own colour. The name is written out either way.
  final Color? locationColor;

  /// "11 AM to 2 PM", or null when RIT gave no time.
  final String? window;

  /// Empty when RIT named no location.
  final String location;

  final TextStyle? style;
  final bool wrap;

  /// What a screen reader says for the two lines, then [status] ("starts at
  /// 4 PM", "ended") for a chef who is not on right now.
  static String label(String? window, String location, {String? status}) =>
      [?window, if (location.isNotEmpty) location, ?status].join(', ');

  @override
  Widget build(BuildContext context) {
    final maxLines = wrap ? null : 1;
    final overflow = wrap ? TextOverflow.clip : TextOverflow.ellipsis;
    final time = window == null
        ? null
        : StatusText(window!, style: style, maxLines: maxLines, overflow: overflow);
    final place = location.isEmpty
        ? null
        : Text(
            location,
            style: locationColor == null ? style : style?.copyWith(color: locationColor),
            maxLines: maxLines,
            overflow: overflow,
          );
    if (!wrap) {
      // one line, the way the wide card has always laid it out
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (time != null) Flexible(child: time),
          if (time != null && place != null) Text(' · ', style: style),
          if (place != null) Flexible(child: place),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [?time, ?place],
    );
  }
}
