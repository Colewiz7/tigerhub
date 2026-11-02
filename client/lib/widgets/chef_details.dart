/// The time and the location of a visiting chef.
///
/// The time sits on the right, centred on the row ([ChefSide]), and the
/// location keeps a line of its own here.
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

/// A chef's text block with the time range on the right, centred on the
/// whole block (name and location), so a row stays two lines tall.
///
/// The time never wraps or clips: it is measured first and the block takes the
/// rest. Only when a word of the name would break in that lane, or the name
/// would lose a line, does the time drop under the block, still right-aligned.
class ChefSide extends StatelessWidget {
  const ChefSide({
    super.key,
    required this.name,
    required this.window,
    required this.titleStyle,
    required this.windowStyle,
    required this.child,
    this.location = '',
    this.nameMaxLines = 2,
  });

  final String name;

  /// The location line's text, so no word of it breaks beside the time.
  final String location;

  /// "11 AM to 2 PM", or null when RIT gave no time.
  final String? window;
  final TextStyle? titleStyle;
  final TextStyle? windowStyle;
  final int nameMaxLines;

  /// The name and the location lines.
  final Widget child;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final time = window;
    if (time == null) return child;

    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    final direction = Directionality.of(context);
    final timeWidget = ExcludeSemantics(
      child: StatusText(time, style: windowStyle, maxLines: 1, overflow: TextOverflow.visible),
    );

    TextPainter paint(String text, TextStyle? style, int lines) => TextPainter(
      text: TextSpan(text: text, style: base.merge(style)),
      textDirection: direction,
      textScaler: scaler,
      maxLines: lines,
    );

    return LayoutBuilder(
      builder: (context, box) {
        // a pixel of slack so a rounded measure never wraps the time
        final timeWidth = (paint(time, windowStyle, 1)..layout()).width + 2;
        final lane = box.maxWidth - timeWidth - _gap;
        var beside = lane > 0;
        if (beside) {
          final narrow = paint(name, titleStyle, nameMaxLines)..layout(maxWidth: lane);
          var wordsWhole = true;
          for (final word in name.split(RegExp(r'\s+'))) {
            if ((paint(word, titleStyle, 1)..layout()).width > lane) wordsWhole = false;
          }
          for (final word in location.split(RegExp(r'\s+'))) {
            if (word.isNotEmpty && (paint(word, windowStyle, 1)..layout()).width > lane) {
              wordsWhole = false;
            }
          }
          beside = !narrow.didExceedMaxLines && wordsWhole;
        }
        if (beside) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: child),
              const SizedBox(width: _gap),
              SizedBox(width: timeWidth, child: Align(alignment: Alignment.centerRight, child: timeWidget)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            Align(alignment: Alignment.centerRight, child: timeWidget),
          ],
        );
      },
    );
  }
}
