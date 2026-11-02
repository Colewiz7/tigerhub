/// The time and the location of a visiting chef.
///
/// The time sits on the right of the name ([ChefTitle]) and the location
/// keeps a line of its own here. (Earlier the two shared a column and the
/// time ended up under the name.)
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

/// A chef's name with the time range on the right.
///
/// The time never wraps or clips: it is measured first and the name takes what
/// is left. If the name would be cut in that lane (large text, long name) the
/// time drops onto its own line under the name, still right-aligned.
class ChefTitle extends StatelessWidget {
  const ChefTitle({
    super.key,
    required this.name,
    required this.window,
    required this.titleStyle,
    required this.windowStyle,
    this.nameMaxLines = 2,
  });

  final String name;

  /// "11 AM to 2 PM", or null when RIT gave no time.
  final String? window;
  final TextStyle? titleStyle;
  final TextStyle? windowStyle;
  final int nameMaxLines;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final nameText = Text(
      name,
      style: titleStyle,
      maxLines: nameMaxLines,
      overflow: TextOverflow.ellipsis,
    );
    final time = window;
    if (time == null) return nameText;

    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    final timeWidget = StatusText(time, style: windowStyle, maxLines: 1, overflow: TextOverflow.visible);

    return LayoutBuilder(
      builder: (context, box) {
        final timePainter = TextPainter(
          text: TextSpan(text: time, style: base.merge(windowStyle)),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        // a pixel of slack so a rounded measure never wraps the time
        final timeWidth = timePainter.width + 2;
        final lane = box.maxWidth - timeWidth - _gap;
        var beside = lane > 0;
        if (beside) {
          final narrow = TextPainter(
            text: TextSpan(text: name, style: base.merge(titleStyle)),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: nameMaxLines,
          )..layout(maxWidth: lane);
          // The time takes the right if the name still fits its lines there
          // and no word breaks mid-way: "KO-BQ" never splits to make room.
          var wordsWhole = true;
          for (final word in name.split(RegExp(r'\s+'))) {
            final w = TextPainter(
              text: TextSpan(text: word, style: base.merge(titleStyle)),
              textDirection: Directionality.of(context),
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (w.width > lane) wordsWhole = false;
          }
          beside = !narrow.didExceedMaxLines && wordsWhole;
        }
        if (beside) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: nameText),
              const SizedBox(width: _gap),
              SizedBox(width: timeWidth, child: Align(alignment: Alignment.centerRight, child: timeWidget)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            nameText,
            Align(alignment: Alignment.centerRight, child: timeWidget),
          ],
        );
      },
    );
  }
}
