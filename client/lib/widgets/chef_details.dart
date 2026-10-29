/// The time and the location of a visiting chef, one line each.
///
/// The Today card used to join both into one subtitle capped at two lines, so
/// the location (written last) was the first thing an ellipsis took. Here each
/// is its own line and neither is ever cut: a long one wraps. From 600pt the
/// card budgets a fixed row height, so [wrap] is off there and each line is
/// held to one.
library;

import 'package:flutter/material.dart';

import 'status_text.dart';

class ChefDetails extends StatelessWidget {
  const ChefDetails({
    super.key,
    required this.window,
    required this.location,
    required this.style,
    this.wrap = true,
  });

  /// "11 AM to 2 PM", or null when RIT gave no time.
  final String? window;

  /// Empty when RIT named no location.
  final String location;

  final TextStyle? style;
  final bool wrap;

  /// What a screen reader says for the two lines.
  static String label(String? window, String location) =>
      [?window, if (location.isNotEmpty) location].join(', ');

  @override
  Widget build(BuildContext context) {
    final maxLines = wrap ? null : 1;
    final overflow = wrap ? TextOverflow.clip : TextOverflow.ellipsis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (window != null)
          StatusText(window!, style: style, maxLines: maxLines, overflow: overflow),
        if (location.isNotEmpty)
          Text(location, style: style, maxLines: maxLines, overflow: overflow),
      ],
    );
  }
}
